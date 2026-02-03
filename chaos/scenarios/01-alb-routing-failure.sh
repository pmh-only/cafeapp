#!/bin/bash
# Chaos Scenario: ALB Routing Failure
#
# Story: A misconfigured deployment accidentally deletes all ALB routing rules,
# causing all incoming traffic to hit the default action (503 Service Unavailable).
#
# Expected Impact:
# - ALB 5XX errors spike to 100%
# - All API requests return 503
# - Target health checks continue to pass (but no routing)
# - CloudWatch dashboard shows red spikes
#
# Duration: Until manually restored
# Severity: HIGH - Complete service outage

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# Check prerequisites
check_aws_cli
check_terraform

# Configuration
SCENARIO_NAME="ALB Routing Failure"
EXPECTED_IMPACT="All traffic returns 503, complete API outage"
OBSERVATION_TIME=60

# Confirm chaos experiment
confirm_chaos "$SCENARIO_NAME" "$EXPECTED_IMPACT"

# Get ALB ARN from Terraform (placeholder - would need load balancing module)
log_info "Retrieving ALB information from Terraform..."

# For this implementation, we'll use AWS CLI to find the ALB
ALB_ARN=$(aws elbv2 describe-load-balancers \
    --query "LoadBalancers[?contains(LoadBalancerName, 'cloudcafe')].LoadBalancerArn" \
    --output text | head -n 1)

if [ -z "$ALB_ARN" ]; then
    log_error "No CloudCafe ALB found. Please deploy infrastructure first."
    exit 1
fi

log_success "Found ALB: $ALB_ARN"

# Get listener ARN
log_info "Finding ALB listener..."
LISTENER_ARN=$(aws elbv2 describe-listeners \
    --load-balancer-arn "$ALB_ARN" \
    --query 'Listeners[0].ListenerArn' \
    --output text)

if [ -z "$LISTENER_ARN" ]; then
    log_error "No listener found on ALB"
    exit 1
fi

log_success "Found listener: $LISTENER_ARN"

# Backup existing rules
log_info "Backing up ALB routing rules..."
RULES=$(aws elbv2 describe-rules \
    --listener-arn "$LISTENER_ARN" \
    --output json)

save_backup "$RULES" "alb_rules_backup_$(date +%Y%m%d_%H%M%S).json"

# Get non-default rule ARNs
RULE_ARNS=$(aws elbv2 describe-rules \
    --listener-arn "$LISTENER_ARN" \
    --query 'Rules[?!IsDefault].RuleArn' \
    --output text)

if [ -z "$RULE_ARNS" ]; then
    log_warning "No custom rules found to delete"
else
    # Delete all non-default rules
    log_warning "🔥 INJECTING CHAOS: Deleting ALB routing rules..."

    for RULE_ARN in $RULE_ARNS; do
        log_info "Deleting rule: $RULE_ARN"
        aws elbv2 delete-rule --rule-arn "$RULE_ARN"
    done

    log_success "✅ Chaos injected: All ALB routing rules deleted"
fi

# Display impact
echo ""
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}🔥 CHAOS ACTIVE: ALB Routing Broken${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Expected CloudWatch Dashboard Indicators:${NC}"
echo "  • ALB 5XX errors → 100%"
echo "  • ALB Request Count → Continues (but all fail)"
echo "  • Target Healthy Host Count → Unchanged (health checks still pass)"
echo "  • Application response time → N/A (requests don't reach targets)"
echo ""
echo -e "${YELLOW}How to verify:${NC}"
echo "  1. Open CloudWatch dashboard"
echo "  2. Check ALB 5XX errors widget"
echo "  3. Try accessing the application (should get 503)"
echo "  4. Note that backend services remain healthy"
echo ""

wait_for_observation $OBSERVATION_TIME

# Restore instructions
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}RESTORE INSTRUCTIONS${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "To restore ALB routing, you have two options:"
echo ""
echo "1. Re-run Terraform (recommended):"
echo "   cd ../../infrastructure/terraform"
echo "   terraform apply"
echo ""
echo "2. Manually restore rules from backup:"
echo "   Backup location: /tmp/cloudcafe-chaos-backups/"
echo "   Restore using: aws elbv2 create-rule ..."
echo ""
log_warning "ALB routing is currently BROKEN. All traffic returns 503."
echo ""
