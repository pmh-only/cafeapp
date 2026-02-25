#!/usr/bin/env bash
# ============================================================
#  CloudCafe — one-command destroy
#  Usage: ./destroy.sh [--region us-east-1] [--env dev] [--yes]
#
#  Pre-destroy steps handled automatically:
#    1. ECS services scaled to 0 and deleted (cluster can't be
#       destroyed while services/tasks are still running)
#    2. EKS workloads deleted (speeds up node-group teardown;
#       LoadBalancer services removed so AWS ELBs are released)
#    3. S3 buckets emptied — objects, versions, delete markers
#       (AWS rejects deletion of non-empty buckets)
#    4. ECR repos force-deleted (images block normal deletion)
#    5. ALB / NLB deletion protection verified off
#    6. RDS / DocDB deletion_protection verified off
#    7. CloudFront — Terraform handles disable→delete itself
#    8. Redshift — skip_final_snapshot=true, no manual step
# ============================================================
set -euo pipefail

# ── defaults ─────────────────────────────────────────────────
REGION="us-east-1"
ENV="dev"
AUTO_YES=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/infrastructure/terraform"

# ── parse args ────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --region) REGION="$2"; shift 2 ;;
    --env)    ENV="$2";    shift 2 ;;
    --yes|-y) AUTO_YES=true; shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# ── colours ───────────────────────────────────────────────────
BOLD='\033[1m'; RED='\033[0;31m'; YELLOW='\033[0;33m'
GREEN='\033[0;32m'; CYAN='\033[0;36m'; RESET='\033[0m'

step() { echo; echo -e "${CYAN}${BOLD}==> $*${RESET}"; }
ok()   { echo -e "    ${GREEN}✓ $*${RESET}"; }
warn() { echo -e "    ${YELLOW}⚠ $*${RESET}"; }
info() { echo -e "    $*"; }
die()  { echo -e "${RED}${BOLD}ERROR: $*${RESET}" >&2; exit 1; }

# ── preflight checks ─────────────────────────────────────────
step "Preflight checks"

command -v aws       > /dev/null || die "aws CLI not found"
command -v terraform > /dev/null || die "terraform not found"

aws sts get-caller-identity --region "$REGION" > /dev/null 2>&1 \
  || die "No valid AWS credentials for region $REGION"
ok "AWS credentials valid"

[[ -f "$TF_DIR/terraform.tfstate" ]] \
  || die "No terraform.tfstate found at $TF_DIR — nothing to destroy"
ok "Terraform state found"

RESOURCE_COUNT=$(python3 -c "
import json
state = json.load(open('$TF_DIR/terraform.tfstate'))
print(sum(len(r.get('instances',[])) for r in state.get('resources',[])))
" 2>/dev/null || echo "?")
ok "State contains ~$RESOURCE_COUNT resource instances"

# ── confirmation ─────────────────────────────────────────────
echo
echo -e "${RED}${BOLD}┌──────────────────────────────────────────────────────┐${RESET}"
echo -e "${RED}${BOLD}│  WARNING — THIS WILL PERMANENTLY DESTROY:            │${RESET}"
echo -e "${RED}${BOLD}│                                                      │${RESET}"
printf  "${RED}${BOLD}│  Region : %-42s│${RESET}\n" "$REGION"
printf  "${RED}${BOLD}│  Env    : %-42s│${RESET}\n" "$ENV"
echo -e "${RED}${BOLD}│                                                      │${RESET}"
echo -e "${RED}${BOLD}│  • All ECS / EKS services and clusters               │${RESET}"
echo -e "${RED}${BOLD}│  • RDS Aurora, DocumentDB, Redshift clusters         │${RESET}"
echo -e "${RED}${BOLD}│  • ElastiCache Redis, MemoryDB                       │${RESET}"
echo -e "${RED}${BOLD}│  • All S3 buckets and their contents                 │${RESET}"
echo -e "${RED}${BOLD}│  • All ECR repos and container images                │${RESET}"
echo -e "${RED}${BOLD}│  • CloudFront, VPC, subnets, security groups         │${RESET}"
echo -e "${RED}${BOLD}│  • SQS queues, Kinesis streams, DynamoDB tables      │${RESET}"
echo -e "${RED}${BOLD}│  • ALL OTHER RESOURCES IN TERRAFORM STATE            │${RESET}"
echo -e "${RED}${BOLD}│                                                      │${RESET}"
echo -e "${RED}${BOLD}│  DATA CANNOT BE RECOVERED AFTER THIS POINT.         │${RESET}"
echo -e "${RED}${BOLD}└──────────────────────────────────────────────────────┘${RESET}"
echo

if [[ "$AUTO_YES" == false ]]; then
  read -r -p "  Type the region to confirm ($REGION): " CONFIRM
  [[ "$CONFIRM" == "$REGION" ]] || { echo "Aborted."; exit 0; }
  echo
  read -r -p "  Are you absolutely sure? Type YES to proceed: " CONFIRM2
  [[ "$CONFIRM2" == "YES" ]] || { echo "Aborted."; exit 0; }
fi

echo
echo -e "${BOLD}Destruction started at $(date -u '+%Y-%m-%d %H:%M:%S UTC')${RESET}"

# ── read cluster names from Terraform outputs ─────────────────
step "Reading Terraform state"
cd "$TF_DIR"

ECS_CLUSTER=$(terraform output -raw ecs_cluster_name 2>/dev/null || echo "")
EKS_CLUSTER=$(terraform output -raw eks_cluster_name 2>/dev/null || echo "")

[[ -n "$ECS_CLUSTER" ]] && ok "ECS cluster: $ECS_CLUSTER" || warn "ECS cluster name not in state"
[[ -n "$EKS_CLUSTER" ]] && ok "EKS cluster: $EKS_CLUSTER" || warn "EKS cluster name not in state"

cd "$SCRIPT_DIR"

# ══════════════════════════════════════════════════════════════
#  PRE-DESTROY STEPS
# ══════════════════════════════════════════════════════════════

# ── STEP 1: ECS — scale to 0 and delete all services ─────────
#
#  Terraform cannot delete an ECS cluster while services/tasks
#  exist.  Scale to 0 first so tasks stop, then delete service
#  objects.  Use --force so deletion doesn't wait for drain.
# ─────────────────────────────────────────────────────────────
step "1/5  ECS — drain and delete all services"

if [[ -n "$ECS_CLUSTER" ]]; then
  mapfile -t SERVICE_ARNS < <(
    aws ecs list-services \
      --cluster "$ECS_CLUSTER" --region "$REGION" \
      --query 'serviceArns[]' --output text 2>/dev/null \
      | tr '\t' '\n' | grep -v '^$' || true
  )

  if [[ ${#SERVICE_ARNS[@]} -eq 0 ]]; then
    warn "No ECS services found in $ECS_CLUSTER"
  else
    # Scale all services to 0 in parallel
    for ARN in "${SERVICE_ARNS[@]}"; do
      SVC=$(basename "$ARN")
      aws ecs update-service \
        --cluster "$ECS_CLUSTER" --service "$SVC" \
        --desired-count 0 --region "$REGION" \
        > /dev/null 2>&1 && info "  scaled $SVC → 0" || warn "could not scale $SVC"
    done

    # Wait up to 3 min for tasks to stop
    info "  Waiting for tasks to drain (up to 3 min)..."
    for i in $(seq 1 18); do
      RUNNING=$(aws ecs list-tasks \
        --cluster "$ECS_CLUSTER" --region "$REGION" \
        --query 'taskArns' --output text 2>/dev/null \
        | wc -w | tr -d ' ')
      [[ "$RUNNING" -eq 0 ]] && break
      info "    $RUNNING task(s) still running — waiting 10s ($i/18)..."
      sleep 10
    done

    # Force-delete all service objects
    for ARN in "${SERVICE_ARNS[@]}"; do
      SVC=$(basename "$ARN")
      aws ecs delete-service \
        --cluster "$ECS_CLUSTER" --service "$SVC" \
        --force --region "$REGION" \
        > /dev/null 2>&1 && ok "deleted service: $SVC" || warn "could not delete $SVC"
    done
  fi
else
  warn "ECS cluster unknown — skipping"
fi

# ── STEP 2: EKS — delete all workloads ───────────────────────
#
#  Delete deployments so pods evict cleanly before node-group
#  teardown.  Delete LoadBalancer-type services explicitly so
#  AWS releases their provisioned ELBs — otherwise those ELBs
#  become orphans outside Terraform's state.
#  Exclude the built-in "kubernetes" ClusterIP service.
# ─────────────────────────────────────────────────────────────
step "2/5  EKS — delete Kubernetes workloads"

if [[ -n "$EKS_CLUSTER" ]]; then
  if aws eks update-kubeconfig \
      --name "$EKS_CLUSTER" --region "$REGION" > /dev/null 2>&1; then
    ok "kubectl configured → $EKS_CLUSTER"

    # Deployments (terminates pods)
    kubectl delete deployments --all --ignore-not-found=true \
      --timeout=120s 2>/dev/null \
      && ok "deployments deleted" || warn "deployment deletion timed out"

    # Only user-created services (skip the built-in 'kubernetes' ClusterIP)
    USER_SVCS=$(kubectl get services \
      --field-selector 'metadata.name!=kubernetes' \
      -o name 2>/dev/null || true)
    if [[ -n "$USER_SVCS" ]]; then
      echo "$USER_SVCS" | xargs kubectl delete --ignore-not-found=true \
        --timeout=60s 2>/dev/null \
        && ok "services deleted" || warn "some services could not be deleted"
    else
      ok "no user services to delete"
    fi

    # Secrets we created during deploy
    kubectl delete secret memorydb-credentials documentdb-credentials \
      elasticache-credentials --ignore-not-found=true 2>/dev/null || true

    # Wait for pods to terminate
    info "  Waiting for pods to terminate..."
    kubectl wait pod --all --for=delete --timeout=90s 2>/dev/null || true
    ok "EKS workloads cleared"
  else
    warn "Could not reach EKS cluster (may already be gone) — skipping"
  fi
else
  warn "EKS cluster unknown — skipping"
fi

# ── STEP 3: S3 — empty all cloudcafe buckets ─────────────────
#
#  AWS rejects deletion of any bucket that still has objects,
#  versioned objects, or delete markers.  We must drain all
#  three categories before Terraform can remove the bucket.
# ─────────────────────────────────────────────────────────────
step "3/5  S3 — empty all cloudcafe buckets"

mapfile -t BUCKETS < <(
  aws s3api list-buckets \
    --query "Buckets[?contains(Name,'cloudcafe')].Name" \
    --output text 2>/dev/null | tr '\t' '\n' | grep -v '^$' || true
)

if [[ ${#BUCKETS[@]} -eq 0 ]]; then
  warn "No cloudcafe S3 buckets found"
else
  for BUCKET in "${BUCKETS[@]}"; do
    info "  emptying s3://$BUCKET ..."

    # 1. Delete all current (non-versioned) objects
    aws s3 rm "s3://$BUCKET" --recursive --region "$REGION" \
      > /dev/null 2>&1 || true

    # 2. Delete all versioned objects and delete markers.
    #    Python calls aws directly to avoid embedding JSON in shell
    #    variables (multi-line JSON with single-quotes breaks eval).
    #    Paginates in batches of 1000 until nothing remains.
    python3 - "$BUCKET" "$REGION" <<'PYEOF'
import sys, json, subprocess

bucket, region = sys.argv[1], sys.argv[2]
total = 0

while True:
    result = subprocess.run(
        ["aws", "s3api", "list-object-versions",
         "--bucket", bucket, "--region", region,
         "--max-items", "1000", "--output", "json"],
        capture_output=True, text=True)

    if result.returncode != 0 or not result.stdout.strip():
        break

    data = json.loads(result.stdout)
    items = []
    for v in (data.get("Versions") or []):
        items.append({"Key": v["Key"], "VersionId": v["VersionId"]})
    for m in (data.get("DeleteMarkers") or []):
        items.append({"Key": m["Key"], "VersionId": m["VersionId"]})

    if not items:
        break

    payload = json.dumps({"Objects": items, "Quiet": True})
    subprocess.run(
        ["aws", "s3api", "delete-objects",
         "--bucket", bucket, "--region", region,
         "--delete", payload],
        capture_output=True)

    total += len(items)
    print(f"    deleted {len(items)} version(s)/delete-marker(s) (total: {total})")

PYEOF

    ok "s3://$BUCKET emptied"
  done
fi

# ── STEP 4: ECR — force-delete all cloudcafe repos ───────────
#
#  aws_ecr_repository in Terraform will not delete a repo that
#  contains images unless force_delete=true was set at resource
#  creation time (ours does not set it).  We delete outside
#  Terraform with --force; Terraform then skips them cleanly.
# ─────────────────────────────────────────────────────────────
step "4/5  ECR — force-delete all cloudcafe repositories"

mapfile -t REPOS < <(
  aws ecr describe-repositories --region "$REGION" \
    --query "repositories[?contains(repositoryName,'cloudcafe')].repositoryName" \
    --output text 2>/dev/null | tr '\t' '\n' | grep -v '^$' || true
)

if [[ ${#REPOS[@]} -eq 0 ]]; then
  warn "No cloudcafe ECR repositories found"
else
  for REPO in "${REPOS[@]}"; do
    aws ecr delete-repository \
      --repository-name "$REPO" --force --region "$REGION" \
      > /dev/null 2>&1 \
      && ok "force-deleted ECR repo: $REPO" \
      || warn "could not delete $REPO (may already be gone)"
  done
fi

# ── STEP 5: Load balancers — ensure deletion protection off ──
#
#  If enable_deletion_protection was ever toggled on manually
#  after deploy, Terraform destroy will error with an explicit
#  API rejection.  We verify and disable it here.
# ─────────────────────────────────────────────────────────────
step "5/5  Load balancers — ensure deletion protection is off"

mapfile -t LB_ARNS < <(
  aws elbv2 describe-load-balancers --region "$REGION" \
    --query "LoadBalancers[?contains(LoadBalancerName,'cloudcafe')].LoadBalancerArn" \
    --output text 2>/dev/null | tr '\t' '\n' | grep -v '^$' || true
)

if [[ ${#LB_ARNS[@]} -eq 0 ]]; then
  warn "No cloudcafe load balancers found"
else
  for ARN in "${LB_ARNS[@]}"; do
    NAME=$(aws elbv2 describe-load-balancers \
      --load-balancer-arns "$ARN" --region "$REGION" \
      --query 'LoadBalancers[0].LoadBalancerName' --output text 2>/dev/null || echo "$ARN")

    PROTECTED=$(aws elbv2 describe-load-balancer-attributes \
      --load-balancer-arn "$ARN" --region "$REGION" \
      --query "Attributes[?Key=='deletion_protection.enabled'].Value" \
      --output text 2>/dev/null || echo "false")

    if [[ "$PROTECTED" == "true" ]]; then
      aws elbv2 modify-load-balancer-attributes \
        --load-balancer-arn "$ARN" --region "$REGION" \
        --attributes Key=deletion_protection.enabled,Value=false \
        > /dev/null
      ok "disabled deletion protection on $NAME"
    else
      ok "$NAME — deletion protection already off"
    fi
  done
fi

# ── Defensive: disable RDS / DocDB deletion_protection ───────
#
#  Our Terraform config has deletion_protection=false, but if
#  it was ever set to true manually we handle it here so
#  terraform destroy doesn't fail at the API level.
# ─────────────────────────────────────────────────────────────
echo
info "Checking RDS / DocDB deletion protection..."

while IFS=$'\t' read -r CLUSTER_ID PROTECTED; do
  [[ -z "$CLUSTER_ID" ]] && continue
  if [[ "$PROTECTED" == "True" ]]; then
    aws rds modify-db-cluster \
      --db-cluster-identifier "$CLUSTER_ID" \
      --no-deletion-protection \
      --apply-immediately \
      --region "$REGION" > /dev/null 2>&1 \
      && ok "disabled deletion protection on $CLUSTER_ID" \
      || warn "could not modify $CLUSTER_ID"
  else
    ok "$CLUSTER_ID — deletion protection already off"
  fi
done < <(
  aws rds describe-db-clusters --region "$REGION" \
    --query "DBClusters[?contains(DBClusterIdentifier,'cloudcafe')].[DBClusterIdentifier,DeletionProtection]" \
    --output text 2>/dev/null || true
)

# ══════════════════════════════════════════════════════════════
#  TERRAFORM DESTROY
# ══════════════════════════════════════════════════════════════
step "Terraform destroy"

cd "$TF_DIR"

# Ensure tfvars targets the right region
case "$REGION" in
  us-east-1)      AZS='["us-east-1a","us-east-1b","us-east-1c"]' ;;
  us-west-2)      AZS='["us-west-2a","us-west-2b","us-west-2c"]' ;;
  ap-northeast-2) AZS='["ap-northeast-2a","ap-northeast-2b","ap-northeast-2c"]' ;;
  eu-west-1)      AZS='["eu-west-1a","eu-west-1b","eu-west-1c"]' ;;
  *)              AZS="[\"${REGION}a\",\"${REGION}b\",\"${REGION}c\"]" ;;
esac

cat > terraform.tfvars <<EOF
aws_region         = "$REGION"
availability_zones = $AZS
EOF

terraform init -reconfigure > /dev/null 2>&1

echo
echo -e "  ${YELLOW}Running terraform destroy — this takes 15–25 minutes.${RESET}"
echo -e "  ${YELLOW}CloudFront propagation alone can take ~10 min.${RESET}"
echo

# Stream filtered output: show progress + errors, suppress noise
terraform destroy -auto-approve -compact-warnings 2>&1 | \
  grep --line-buffered -E \
    'Destroying\.\.\.|still destroying|Destruction complete|Error|Warning|0 destroyed' | \
  while IFS= read -r line; do
    if   echo "$line" | grep -qi "error";    then echo -e "  ${RED}$line${RESET}"
    elif echo "$line" | grep -qi "complete|destroyed"; then echo -e "  ${GREEN}$line${RESET}"
    else echo "  $line"
    fi
  done

cd "$SCRIPT_DIR"

# ══════════════════════════════════════════════════════════════
#  POST-DESTROY CLEANUP
# ══════════════════════════════════════════════════════════════
step "Post-destroy cleanup"

rm -f "$TF_DIR/tfplan" "$TF_DIR/tfplan-us-east-1" 2>/dev/null || true
rm -f "$TF_DIR/terraform.tfstate.backup"           2>/dev/null || true
rm -f "$TF_DIR/modules/serverless/lambda_placeholder.zip" \
      "$TF_DIR/modules/serverless/handler.py"      2>/dev/null || true
ok "Local Terraform artefacts removed"

# Remove the stale kubectl context for the destroyed cluster
if [[ -n "$EKS_CLUSTER" ]]; then
  ACCOUNT_ID=$(aws sts get-caller-identity \
    --query Account --output text 2>/dev/null || echo "")
  if [[ -n "$ACCOUNT_ID" ]]; then
    CTX="arn:aws:eks:${REGION}:${ACCOUNT_ID}:cluster/${EKS_CLUSTER}"
    kubectl config delete-context "$CTX" 2>/dev/null \
      && ok "kubectl context removed" || true
  fi
fi

# ── final status ─────────────────────────────────────────────
echo
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

REMAINING=$(python3 -c "
import json
try:
    state = json.load(open('$TF_DIR/terraform.tfstate'))
    print(sum(len(r.get('instances',[])) for r in state.get('resources',[])))
except:
    print(0)
" 2>/dev/null || echo "0")

if [[ "$REMAINING" == "0" ]]; then
  echo -e "${GREEN}${BOLD}  Destroy complete — 0 resources remaining in state.${RESET}"
else
  echo -e "${YELLOW}${BOLD}  Destroy finished with $REMAINING resource(s) still in state.${RESET}"
  echo -e "${YELLOW}  Inspect with: terraform -chdir=$TF_DIR state list${RESET}"
fi

echo
echo -e "  Completed at $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
