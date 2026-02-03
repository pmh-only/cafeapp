#!/bin/bash
# Chaos Scenario: EKS Node Drain
#
# Story: A Kubernetes node upgrade drains pods without proper Pod Disruption
# Budget (PDB). All pods on the node are evicted simultaneously, causing a
# brief capacity crunch as they reschedule to other nodes.
#
# Expected Impact:
# - Pod count drops temporarily
# - Remaining nodes experience increased CPU/memory pressure
# - Brief API errors (503) during pod rescheduling
# - Pod restart count increases
# - VPC Lattice 5XX errors may spike
# - Auto-scaling triggers new node provisioning
#
# Duration: 2-5 minutes (until pods fully rescheduled)
# Severity: MEDIUM - Temporary capacity reduction

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# Check prerequisites
check_required_tools aws kubectl
check_terraform

# Configuration
SCENARIO_NAME="EKS Node Drain (Pod Eviction)"
EXPECTED_IMPACT="Pods evicted, CPU spike on remaining nodes, brief 5XX errors"
OBSERVATION_TIME=180

# Confirm chaos experiment
confirm_chaos "$SCENARIO_NAME" "$EXPECTED_IMPACT"

# Get EKS cluster name from Terraform
log_info "Retrieving EKS cluster information from Terraform..."

CLUSTER_NAME=$(get_terraform_output "eks_cluster_name")

if [ -z "$CLUSTER_NAME" ]; then
    log_error "EKS cluster name not found in Terraform outputs"
    exit 1
fi

log_success "Found EKS cluster: $CLUSTER_NAME"

# Update kubeconfig
log_info "Updating kubeconfig..."
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region us-east-1 > /dev/null 2>&1

# Verify kubectl access
if ! kubectl get nodes > /dev/null 2>&1; then
    log_error "Cannot access Kubernetes cluster"
    log_info "Ensure you have kubectl installed and AWS credentials configured"
    exit 1
fi

# Get list of nodes
log_info "Listing EKS nodes..."

NODES=$(kubectl get nodes --no-headers -o custom-columns=":metadata.name")
NODE_COUNT=$(echo "$NODES" | wc -l)

if [ "$NODE_COUNT" -lt 2 ]; then
    log_error "Cluster has only $NODE_COUNT node(s)"
    log_info "Node drain requires at least 2 nodes to safely reschedule pods"
    exit 1
fi

log_success "Cluster has $NODE_COUNT nodes (safe for drain)"

# Select first node to drain
TARGET_NODE=$(echo "$NODES" | head -n 1)
log_info "Target node for drain: $TARGET_NODE"

# Get pod count before drain
PODS_BEFORE=$(kubectl get pods --all-namespaces --field-selector spec.nodeName=$TARGET_NODE --no-headers | wc -l)
log_info "Pods on target node: $PODS_BEFORE"

# Backup node info
BACKUP_DIR=$(create_backup_dir)
kubectl get node "$TARGET_NODE" -o yaml > "$BACKUP_DIR/node_${TARGET_NODE}.yaml"
kubectl get pods --all-namespaces --field-selector spec.nodeName=$TARGET_NODE -o yaml > "$BACKUP_DIR/pods_${TARGET_NODE}.yaml"
log_success "Node and pod info backed up"

# Inject chaos
echo ""
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}🔥 INJECTING CHAOS: Draining EKS Node${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

log_warning "Cordoning node: $TARGET_NODE"
kubectl cordon "$TARGET_NODE"

log_warning "Draining node (forcing pod eviction)..."
kubectl drain "$TARGET_NODE" \
    --ignore-daemonsets \
    --delete-emptydir-data \
    --force \
    --grace-period=30 \
    --timeout=300s

log_success "✅ Chaos injected: Node drained"

# Display impact
echo ""
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}🔥 CHAOS ACTIVE: EKS Node Drained${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Expected CloudWatch Dashboard Indicators:${NC}"
echo "  • EKS Pod CPU Utilization → Spikes on remaining nodes"
echo "  • EKS Pod Memory Utilization → Increases on other nodes"
echo "  • Pod Restart Count → Increases for evicted pods"
echo "  • VPC Lattice 5XX Errors → Brief spike during transition"
echo "  • ALB 5XX Errors → May spike if unhealthy pods targeted"
echo ""
echo -e "${YELLOW}Recovery Timeline:${NC}"
echo "  • T+0s:   Node cordoned and drained"
echo "  • T+30s:  Pods begin rescheduling to other nodes"
echo "  • T+90s:  Most pods running on new nodes"
echo "  • T+180s: All pods healthy, node still cordoned"
echo ""
echo -e "${YELLOW}Pods Affected:${NC}"
echo "  • Total pods evicted: $PODS_BEFORE"
echo "  • Rescheduling target: Other $((NODE_COUNT - 1)) nodes"
echo ""
echo -e "${YELLOW}How to verify:${NC}"
echo "  1. Watch pod status: kubectl get pods --all-namespaces -w"
echo "  2. Check node status: kubectl get nodes"
echo "  3. Monitor CloudWatch dashboard for CPU/memory spikes"
echo "  4. Check VPC Lattice metrics for 5XX errors"
echo ""

# Monitor recovery
log_info "Monitoring pod recovery..."

for i in {1..12}; do
    sleep 15

    PENDING=$(kubectl get pods --all-namespaces --field-selector status.phase=Pending --no-headers 2>/dev/null | wc -l)
    RUNNING=$(kubectl get pods --all-namespaces --field-selector status.phase=Running --no-headers 2>/dev/null | wc -l)

    echo "[${i}m] Pending: $PENDING | Running: $RUNNING"
done

wait_for_observation 30

# Check recovery
log_info "Checking recovery status..."

PODS_ON_NODE=$(kubectl get pods --all-namespaces --field-selector spec.nodeName=$TARGET_NODE --no-headers 2>/dev/null | wc -l)
PENDING_PODS=$(kubectl get pods --all-namespaces --field-selector status.phase=Pending --no-headers 2>/dev/null | wc -l)

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}RECOVERY STATUS${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Original pods on node: $PODS_BEFORE"
echo "Current pods on node: $PODS_ON_NODE"
echo "Pending pods cluster-wide: $PENDING_PODS"
echo ""

if [ "$PENDING_PODS" -eq 0 ]; then
    log_success "✅ All pods rescheduled successfully!"
else
    log_warning "⏳ $PENDING_PODS pods still pending (may need more time)"
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}RESTORE INSTRUCTIONS${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "The node is currently CORDONED (unschedulable)."
echo ""
echo "To restore the node for scheduling:"
echo "  kubectl uncordon $TARGET_NODE"
echo ""
echo "To verify node is schedulable:"
echo "  kubectl get node $TARGET_NODE"
echo "  (Status should show 'Ready' without 'SchedulingDisabled')"
echo ""
log_warning "Node remains cordoned to prevent automatic pod scheduling"
log_info "Uncordon manually when ready, or leave cordoned for extended observation"
echo ""
