#!/usr/bin/env bash
# ============================================================
#  CloudCafe — one-command deploy
#  Usage: ./deploy.sh [--region us-east-1] [--env dev]
# ============================================================
set -euo pipefail

# ── defaults ─────────────────────────────────────────────────
REGION="us-east-1"
ENV="dev"
ACCOUNT_ID="972209100553"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/infrastructure/terraform"

# ── parse args ────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --region) REGION="$2"; shift 2 ;;
    --env)    ENV="$2";    shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

ECR="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

# ── helpers ───────────────────────────────────────────────────
BOLD='\033[1m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'
YELLOW='\033[0;33m'; RESET='\033[0m'

step()  { echo; echo -e "${CYAN}${BOLD}==> $*${RESET}"; }
ok()    { echo -e "    ${GREEN}✓ $*${RESET}"; }
warn()  { echo -e "    ${YELLOW}⚠ $*${RESET}"; }

ecr_ensure() {
  aws ecr describe-repositories --repository-names "$1" --region "$REGION" \
    > /dev/null 2>&1 || \
  aws ecr create-repository \
    --repository-name "$1" --region "$REGION" \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=AES256 > /dev/null
}

build_push() {
  local name="$1" context="$2"
  ecr_ensure "$name"
  docker build -q -t "$name:latest" "$context"
  docker tag "$name:latest" "$ECR/$name:latest"
  docker push -q "$ECR/$name:latest" > /dev/null
  ok "$name image pushed"
}

ecs_log_group() {
  aws logs create-log-group --log-group-name "/ecs/$1" \
    --region "$REGION" 2>/dev/null || true
}

ecs_register() {
  aws ecs register-task-definition \
    --cli-input-json "file://$1" --region "$REGION" > /dev/null
}

ecs_deploy() {
  local svc="$1" task="$2" count="$3" tg_name="${4:-}"
  local net="awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$TASK_SG],assignPublicIp=DISABLED}"

  # Build args
  local args=(
    --cluster "$ECS_CLUSTER" --service-name "$svc"
    --task-definition "$task" --desired-count "$count"
    --launch-type FARGATE
    --network-configuration "$net"
    --region "$REGION"
  )

  # Attach ALB target group when one is provided
  if [[ -n "$tg_name" ]]; then
    local tg_arn
    tg_arn=$(aws elbv2 describe-target-groups --names "$tg_name" \
      --region "$REGION" --query 'TargetGroups[0].TargetGroupArn' \
      --output text 2>/dev/null || true)
    if [[ -n "$tg_arn" && "$tg_arn" != "None" ]]; then
      # Fargate (awsvpc) requires target type = ip
      local tg_type
      tg_type=$(aws elbv2 describe-target-groups --target-group-arns "$tg_arn" \
        --region "$REGION" --query 'TargetGroups[0].TargetType' \
        --output text 2>/dev/null || echo "instance")
      if [[ "$tg_type" == "ip" ]]; then
        args+=(
          --load-balancers "targetGroupArn=$tg_arn,containerName=${svc},containerPort=8080"
          --health-check-grace-period-seconds 60
        )
      else
        warn "$tg_name skipped (target type '$tg_type' incompatible with Fargate awsvpc)"
      fi
    fi
  fi

  # Create or update
  if aws ecs describe-services --cluster "$ECS_CLUSTER" --services "$svc" \
       --region "$REGION" --query 'services[0].status' \
       --output text 2>/dev/null | grep -q "ACTIVE"; then
    aws ecs update-service "${args[@]/--launch-type FARGATE/}" \
      --launch-type FARGATE > /dev/null 2>&1 || \
    aws ecs update-service --cluster "$ECS_CLUSTER" --service "$svc" \
      --task-definition "$task" --desired-count "$count" \
      --region "$REGION" > /dev/null
    ok "$svc updated"
  else
    aws ecs create-service "${args[@]}" > /dev/null
    ok "$svc created"
  fi
}

# ══════════════════════════════════════════════════════════════
echo
echo -e "${BOLD}CloudCafe deploy → region: $REGION  env: $ENV${RESET}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 1. TERRAFORM ─────────────────────────────────────────────
step "1/6  Infrastructure (Terraform)"

# Write tfvars for the requested region
case "$REGION" in
  us-east-1)      AZS='["us-east-1a","us-east-1b","us-east-1c"]' ;;
  us-west-2)      AZS='["us-west-2a","us-west-2b","us-west-2c"]' ;;
  ap-northeast-2) AZS='["ap-northeast-2a","ap-northeast-2b","ap-northeast-2c"]' ;;
  eu-west-1)      AZS='["eu-west-1a","eu-west-1b","eu-west-1c"]' ;;
  *)              AZS="[\"${REGION}a\",\"${REGION}b\",\"${REGION}c\"]" ;;
esac

cat > "$TF_DIR/terraform.tfvars" <<EOF
aws_region         = "$REGION"
availability_zones = $AZS
EOF

cd "$TF_DIR"
terraform init -upgrade -reconfigure > /dev/null
ok "terraform init done"

terraform plan -out=tfplan -compact-warnings -input=false > /dev/null
ok "terraform plan done"

terraform apply -auto-approve -compact-warnings tfplan > /dev/null
ok "terraform apply done ($(terraform output 2>/dev/null | wc -l | tr -d ' ') outputs)"

# Read outputs
VPC_ID=$(terraform output -raw vpc_id)
ECS_CLUSTER=$(terraform output -raw ecs_cluster_name)
EKS_CLUSTER=$(terraform output -raw eks_cluster_name)
TASK_SG=$(terraform output -raw ecs_task_security_group_id)
RDS=$(terraform output -raw rds_cluster_endpoint)
REDIS=$(terraform output -raw elasticache_endpoint)
MEMORYDB=$(terraform output -raw memorydb_cluster_endpoint)
KINESIS_ORDER=$(terraform output -raw order_events_stream_name)
KINESIS_ANALYTICS=$(terraform output -json kinesis_stream_names | jq -r '.[1]')
DY_ORDERS=$(terraform output -json dynamodb_table_names | jq -r '.active_orders')
DY_MENU=$(terraform output -json dynamodb_table_names   | jq -r '.menu_catalog')
DY_INV=$(terraform output -json dynamodb_table_names    | jq -r '.store_inventory')
ALB_DNS=$(terraform output -raw alb_dns_name)
API_GW=$(terraform output -raw api_gateway_url)
CF_URL=$(terraform output -raw cloudfront_url)
cd "$SCRIPT_DIR"

SUBNETS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Type,Values=private" \
  --query 'Subnets[*].SubnetId' --output text --region "$REGION" | tr '\t' ',')

# ── 2. ECR LOGIN ─────────────────────────────────────────────
step "2/6  ECR login"
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$ECR" > /dev/null 2>&1
ok "authenticated to $ECR"

# ── 3. BUILD & PUSH — ECS SERVICES ──────────────────────────
step "3/6  Build & push ECS images"

# ---- Order Service (Python) ----------------------------
build_push cloudcafe-order-service "$SCRIPT_DIR/services/order-service"

# ---- Loyalty Service (inline Flask) --------------------
LOYALTY_DIR=$(mktemp -d)
cat > "$LOYALTY_DIR/app.py" <<'PYEOF'
from flask import Flask, jsonify, request
from datetime import datetime
import os

app = Flask(__name__)

@app.route('/health')
def health():
    return jsonify({'status':'healthy','service':'loyalty-service',
                    'timestamp':datetime.utcnow().isoformat()}), 200

@app.route('/loyalty/points/<user_id>')
def get_points(user_id):
    return jsonify({'user_id':user_id,'points':1250,'tier':'gold','status':'active'}), 200

@app.route('/loyalty/points/add', methods=['POST'])
def add_points():
    data = request.json or {}
    return jsonify({'status':'success','points_added':data.get('points',0),'new_balance':1500}), 200

@app.route('/loyalty/tier/<user_id>')
def get_tier(user_id):
    return jsonify({'user_id':user_id,'tier':'gold','benefits':['free_drink','birthday_reward']}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
PYEOF
cat > "$LOYALTY_DIR/requirements.txt" <<'EOF'
flask==3.0.0
gunicorn==21.2.0
boto3==1.34.0
EOF
cat > "$LOYALTY_DIR/Dockerfile" <<'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')" || exit 1
CMD ["gunicorn","-b","0.0.0.0:8080","app:app","--workers","4","--timeout","120"]
EOF
build_push cloudcafe-loyalty-service "$LOYALTY_DIR"
rm -rf "$LOYALTY_DIR"

# ---- Analytics Worker (inline Python) ------------------
ANALYTICS_DIR=$(mktemp -d)
cat > "$ANALYTICS_DIR/worker.py" <<'PYEOF'
import boto3, json, time, logging
from datetime import datetime
import os

logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
logger = logging.getLogger(__name__)

region      = os.getenv('AWS_REGION', 'us-east-1')
STREAM_NAME = os.getenv('KINESIS_STREAM', 'cloudcafe-analytics-events-dev')
kinesis     = boto3.client('kinesis', region_name=region)

def main():
    logger.info("Analytics Worker starting — stream: %s", STREAM_NAME)
    try:
        shards = kinesis.describe_stream(StreamName=STREAM_NAME)
        shard_id = shards['StreamDescription']['Shards'][0]['ShardId']
        iterator = kinesis.get_shard_iterator(
            StreamName=STREAM_NAME, ShardId=shard_id,
            ShardIteratorType='LATEST')['ShardIterator']
        logger.info("Listening on shard %s", shard_id)
        while True:
            try:
                resp = kinesis.get_records(ShardIterator=iterator, Limit=100)
                if resp['Records']:
                    logger.info("Processed %d records", len(resp['Records']))
                iterator = resp['NextShardIterator']
                time.sleep(1)
            except Exception as e:
                logger.error("Loop error: %s", e)
                time.sleep(5)
    except Exception as e:
        logger.error("Fatal: %s", e)
        time.sleep(10)

if __name__ == '__main__':
    main()
PYEOF
cat > "$ANALYTICS_DIR/requirements.txt" <<'EOF'
boto3==1.34.0
EOF
cat > "$ANALYTICS_DIR/Dockerfile" <<'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY worker.py .
CMD ["python","worker.py"]
EOF
build_push cloudcafe-analytics-worker "$ANALYTICS_DIR"
rm -rf "$ANALYTICS_DIR"

# ── 4. DEPLOY ECS SERVICES ───────────────────────────────────
step "4/6  Deploy ECS services"

# Task definitions are written to temp files then registered
ecs_log_group cloudcafe-order-service
cat > /tmp/td-order.json <<EOF
{
  "family": "cloudcafe-order-service",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512", "memory": "1024",
  "executionRoleArn": "arn:aws:iam::${ACCOUNT_ID}:role/cloudcafe-ecs-task-execution-${ENV}",
  "taskRoleArn":      "arn:aws:iam::${ACCOUNT_ID}:role/cloudcafe-ecs-task-${ENV}",
  "containerDefinitions": [{
    "name": "order-service",
    "image": "${ECR}/cloudcafe-order-service:latest",
    "portMappings": [{"containerPort": 8080}],
    "environment": [
      {"name":"ENVIRONMENT",                  "value":"${ENV}"},
      {"name":"AWS_REGION",                   "value":"${REGION}"},
      {"name":"REDIS_HOST",                   "value":"${REDIS}"},
      {"name":"REDIS_PORT",                   "value":"6379"},
      {"name":"DB_HOST",                      "value":"${RDS}"},
      {"name":"DB_PORT",                      "value":"5432"},
      {"name":"DB_NAME",                      "value":"cloudcafe"},
      {"name":"DB_USER",                      "value":"cloudcafe_admin"},
      {"name":"DB_PASSWORD",                  "value":"CloudCafe2024!"},
      {"name":"KINESIS_ORDER_EVENTS_STREAM",  "value":"${KINESIS_ORDER}"},
      {"name":"DYNAMODB_ACTIVE_ORDERS_TABLE", "value":"${DY_ORDERS}"}
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/cloudcafe-order-service",
        "awslogs-region": "${REGION}",
        "awslogs-stream-prefix": "ecs"
      }
    },
    "healthCheck": {
      "command": ["CMD-SHELL","curl -f http://localhost:8080/health || exit 1"],
      "interval":30,"timeout":5,"retries":3,"startPeriod":60
    }
  }]
}
EOF
ecs_register /tmp/td-order.json
ecs_deploy order-service cloudcafe-order-service 2 cloudcafe-order-tg-${ENV}

ecs_log_group cloudcafe-loyalty-service
cat > /tmp/td-loyalty.json <<EOF
{
  "family": "cloudcafe-loyalty-service",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256", "memory": "512",
  "executionRoleArn": "arn:aws:iam::${ACCOUNT_ID}:role/cloudcafe-ecs-task-execution-${ENV}",
  "taskRoleArn":      "arn:aws:iam::${ACCOUNT_ID}:role/cloudcafe-ecs-task-${ENV}",
  "containerDefinitions": [{
    "name": "loyalty-service",
    "image": "${ECR}/cloudcafe-loyalty-service:latest",
    "portMappings": [{"containerPort": 8080}],
    "environment": [
      {"name":"ENVIRONMENT","value":"${ENV}"},
      {"name":"AWS_REGION", "value":"${REGION}"}
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/cloudcafe-loyalty-service",
        "awslogs-region": "${REGION}",
        "awslogs-stream-prefix": "ecs"
      }
    },
    "healthCheck": {
      "command": ["CMD-SHELL","curl -f http://localhost:8080/health || exit 1"],
      "interval":30,"timeout":5,"retries":3,"startPeriod":60
    }
  }]
}
EOF
ecs_register /tmp/td-loyalty.json
ecs_deploy loyalty-service cloudcafe-loyalty-service 2 cloudcafe-loyalty-tg-${ENV}

ecs_log_group cloudcafe-analytics-worker
cat > /tmp/td-analytics.json <<EOF
{
  "family": "cloudcafe-analytics-worker",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256", "memory": "512",
  "executionRoleArn": "arn:aws:iam::${ACCOUNT_ID}:role/cloudcafe-ecs-task-execution-${ENV}",
  "taskRoleArn":      "arn:aws:iam::${ACCOUNT_ID}:role/cloudcafe-ecs-task-${ENV}",
  "containerDefinitions": [{
    "name": "analytics-worker",
    "image": "${ECR}/cloudcafe-analytics-worker:latest",
    "environment": [
      {"name":"ENVIRONMENT",    "value":"${ENV}"},
      {"name":"AWS_REGION",     "value":"${REGION}"},
      {"name":"KINESIS_STREAM", "value":"${KINESIS_ANALYTICS}"}
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/cloudcafe-analytics-worker",
        "awslogs-region": "${REGION}",
        "awslogs-stream-prefix": "ecs"
      }
    }
  }]
}
EOF
ecs_register /tmp/td-analytics.json
ecs_deploy analytics-worker cloudcafe-analytics-worker 1

# ── 5. BUILD & DEPLOY EKS SERVICES ──────────────────────────
step "5/6  Build & push EKS images + deploy"

aws eks update-kubeconfig --name "$EKS_CLUSTER" --region "$REGION" > /dev/null
ok "kubectl configured → $EKS_CLUSTER"

# ---- Menu Service (Node.js) ----------------------------
build_push cloudcafe-menu-service "$SCRIPT_DIR/services/menu-service"
sed "s|\${AWS_ACCOUNT_ID}|$ACCOUNT_ID|g; s|\${AWS_REGION}|$REGION|g; s|ap-northeast-2|$REGION|g" \
  "$SCRIPT_DIR/services/menu-service/k8s/deployment.yaml" \
  | kubectl apply -f - > /dev/null
[[ -f "$SCRIPT_DIR/services/menu-service/k8s/service.yaml" ]] && \
  kubectl apply -f "$SCRIPT_DIR/services/menu-service/k8s/service.yaml" > /dev/null || true
ok "menu-service deployed to EKS"

# ---- Inventory Service (Go) ----------------------------
build_push cloudcafe-inventory-service "$SCRIPT_DIR/services/inventory-service"
kubectl create secret generic memorydb-credentials \
  --from-literal=endpoint="$MEMORYDB" \
  --dry-run=client -o yaml | kubectl apply -f - > /dev/null
sed "s|\${AWS_ACCOUNT_ID}|$ACCOUNT_ID|g; s|\${AWS_REGION}|$REGION|g; s|ap-northeast-2|$REGION|g" \
  "$SCRIPT_DIR/services/inventory-service/k8s/deployment.yaml" \
  | kubectl apply -f - > /dev/null
[[ -f "$SCRIPT_DIR/services/inventory-service/k8s/service.yaml" ]] && \
  kubectl apply -f "$SCRIPT_DIR/services/inventory-service/k8s/service.yaml" > /dev/null || true
ok "inventory-service deployed to EKS"

# ── 6. STATUS ────────────────────────────────────────────────
step "6/6  Status"

echo
printf "  %-22s %s\n" "ECS Services" ""
aws ecs describe-services \
  --cluster "$ECS_CLUSTER" \
  --services order-service loyalty-service analytics-worker \
  --region "$REGION" \
  --query 'services[*].{Service:serviceName,Status:status,Running:runningCount,Desired:desiredCount}' \
  --output table 2>&1 | sed 's/^/  /'

echo
printf "  %-22s %s\n" "EKS Pods" ""
kubectl get pods -o wide 2>&1 | sed 's/^/  /'

echo
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${GREEN}${BOLD}  Deployment complete!${RESET}"
echo
echo "  ALB:         http://$ALB_DNS"
echo "  API Gateway: $API_GW"
echo "  CloudFront:  $CF_URL"
echo
echo "  Tasks start in ~2 min. Check with:"
echo "    aws ecs describe-services --cluster $ECS_CLUSTER \\"
echo "      --services order-service loyalty-service analytics-worker \\"
echo "      --region $REGION --query 'services[*].{svc:serviceName,run:runningCount}'"
echo "    kubectl get pods"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
