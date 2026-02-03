#!/bin/bash
# Chaos Scenario: ECS Task Kill
#
# Story: A node failure in the ECS cluster causes 50% of running tasks to
# terminate unexpectedly. ECS auto-recovery kicks in, but there's a brief
# period where capacity is reduced, causing CPU spikes on remaining tasks.
#
# Expected Impact:
# - ECS running task count drops by 50%
# - Remaining tasks experience CPU spike (doubled load)
# - ALB may show brief 5XX errors during transition
# - New tasks start within 60-90 seconds
# - CloudWatch shows task count drop and CPU spike
#
# Duration: 60-120 seconds (until tasks recover)
# Severity: MEDIUM - Temporary capacity reduction

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# Check prerequisites
check_aws_cli
check_terraform

# Configuration
SCENARIO_NAME="ECS Task Kill (50% capacity loss)"
EXPECTED_IMPACT="Task count drops 50%, CPU spikes on remaining tasks, brief 5XX errors"
OBSERVATION_TIME=120

# Confirm chaos experiment
confirm_chaos "$SCENARIO_NAME" "$EXPECTED_IMPACT"

# Get ECS cluster and service info from Terraform
log_info "Retrieving ECS cluster information from Terraform..."

CLUSTER_NAME=$(get_terraform_output "ecs_cluster_name")

if [ -z "$CLUSTER_NAME" ]; then
    log_error "ECS cluster name not found in Terraform outputs"
    exit 1
fi

log_success "Found ECS cluster: $CLUSTER_NAME"

# Get service name (assuming order-service)
SERVICE_NAME="order-service"

log_info "Checking if service '$SERVICE_NAME' exists..."

# Verify service exists
SERVICE_EXISTS=$(aws ecs describe-services \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --query 'services[0].serviceName' \
    --output text 2>/dev/null || echo "")

if [ "$SERVICE_EXISTS" != "$SERVICE_NAME" ]; then
    log_warning "Service '$SERVICE_NAME' not found. Looking for any service..."

    # Find any service in the cluster
    SERVICE_NAME=$(aws ecs list-services \
        --cluster "$CLUSTER_NAME" \
        --query 'serviceArns[0]' \
        --output text | awk -F/ '{print $NF}')

    if [ -z "$SERVICE_NAME" ] || [ "$SERVICE_NAME" == "None" ]; then
        log_error "No ECS services found in cluster $CLUSTER_NAME"
        log_info "Please deploy a service first"
        exit 1
    fi

    log_success "Found service: $SERVICE_NAME"
fi

# Get running tasks
log_info "Listing running tasks for service '$SERVICE_NAME'..."

TASK_ARNS=$(aws ecs list-tasks \
    --cluster "$CLUSTER_NAME" \
    --service-name "$SERVICE_NAME" \
    --desired-status RUNNING \
    --query 'taskArns' \
    --output text)

if [ -z "$TASK_ARNS" ]; then
    log_error "No running tasks found for service $SERVICE_NAME"
    exit 1
fi

# Count tasks
TASK_COUNT=$(echo "$TASK_ARNS" | wc -w)
KILL_COUNT=$((TASK_COUNT / 2))

if [ $KILL_COUNT -eq 0 ]; then
    KILL_COUNT=1
fi

log_success "Found $TASK_COUNT running tasks"
log_warning "Will kill $KILL_COUNT tasks (50%)"

# Inject chaos
echo ""
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}🔥 INJECTING CHAOS: Killing 50% of ECS tasks${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Kill tasks
KILLED_COUNT=0
for TASK_ARN in $TASK_ARNS; do
    if [ $KILLED_COUNT -ge $KILL_COUNT ]; then
        break
    fi

    TASK_ID=$(echo "$TASK_ARN" | awk -F/ '{print $NF}')
    log_info "Stopping task: $TASK_ID"

    aws ecs stop-task \
        --cluster "$CLUSTER_NAME" \
        --task "$TASK_ARN" \
        --reason "Chaos experiment: Node failure simulation" \
        --output json > /dev/null

    KILLED_COUNT=$((KILLED_COUNT + 1))
done

log_success "✅ Chaos injected: Killed $KILLED_COUNT tasks"

# Display impact
echo ""
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}🔥 CHAOS ACTIVE: ECS Task Capacity Reduced${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Expected CloudWatch Dashboard Indicators:${NC}"
echo "  • ECS Running Task Count → Drops from $TASK_COUNT to $((TASK_COUNT - KILLED_COUNT))"
echo "  • ECS Task CPU Utilization → Spikes (2x load per task)"
echo "  • ALB 5XX Errors → Brief spike during transition"
echo "  • ALB Target Healthy Host Count → Temporarily reduced"
echo "  • ECS Service Desired Count → Unchanged (ECS will recover)"
echo ""
echo -e "${YELLOW}Recovery Timeline:${NC}"
echo "  • T+0s:   Tasks killed"
echo "  • T+10s:  ECS detects task shortage"
echo "  • T+30s:  New tasks starting"
echo "  • T+90s:  New tasks healthy and serving traffic"
echo "  • T+120s: Full capacity restored"
echo ""
echo -e "${YELLOW}How to verify:${NC}"
echo "  1. Open CloudWatch dashboard"
echo "  2. Watch ECS running task count drop"
echo "  3. Watch CPU utilization spike on remaining tasks"
echo "  4. Watch new tasks appear as ECS recovers"
echo "  5. Note brief ALB 5XX errors during transition"
echo ""

wait_for_observation $OBSERVATION_TIME

# Check recovery
log_info "Checking task recovery..."

CURRENT_TASK_COUNT=$(aws ecs list-tasks \
    --cluster "$CLUSTER_NAME" \
    --service-name "$SERVICE_NAME" \
    --desired-status RUNNING \
    --query 'taskArns' \
    --output text | wc -w)

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}RECOVERY STATUS${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Original task count: $TASK_COUNT"
echo "Tasks killed: $KILLED_COUNT"
echo "Current task count: $CURRENT_TASK_COUNT"
echo ""

if [ "$CURRENT_TASK_COUNT" -ge "$TASK_COUNT" ]; then
    log_success "✅ Full recovery complete! All tasks restored."
else
    log_warning "⏳ Recovery in progress ($CURRENT_TASK_COUNT/$TASK_COUNT tasks)"
    log_info "ECS will continue to start tasks until desired count is reached"
fi

echo ""
log_info "No manual restoration needed - ECS auto-recovery handles this"
echo ""
