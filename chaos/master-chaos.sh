#!/bin/bash
# Master Chaos Engineering Orchestrator
#
# This script runs multiple chaos scenarios in sequence to comprehensively
# test the CloudCafe infrastructure's resilience and observability.
#
# Scenarios executed:
# 1. ECS Task Kill (compute failure)
# 2. RDS Failover (database failure)
# 3. ElastiCache Flush (cache failure)
# 4. ALB Routing Failure (network failure)
#
# Total duration: ~8 minutes
# Severity: Progressive (MEDIUM → HIGH)

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# Colors
PURPLE='\033[0;35m'
CYAN='\033[0;36m'

# Configuration
SCENARIO_DIR="$SCRIPT_DIR/scenarios"
PAUSE_BETWEEN_SCENARIOS=30

# Banner
clear
echo -e "${PURPLE}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║   ██████╗██╗      ██████╗ ██╗   ██╗██████╗  ██████╗ █████╗  ║
║  ██╔════╝██║     ██╔═══██╗██║   ██║██╔══██╗██╔════╝██╔══██╗ ║
║  ██║     ██║     ██║   ██║██║   ██║██║  ██║██║     ███████║ ║
║  ██║     ██║     ██║   ██║██║   ██║██║  ██║██║     ██╔══██║ ║
║  ╚██████╗███████╗╚██████╔╝╚██████╔╝██████╔╝╚██████╗██║  ██║ ║
║   ╚═════╝╚══════╝ ╚═════╝  ╚═════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝ ║
║                                                               ║
║          🔥 MASTER CHAOS ENGINEERING EXPERIMENT 🔥           ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo ""
echo -e "${CYAN}This script will execute multiple chaos scenarios to test:${NC}"
echo "  • Infrastructure resilience"
echo "  • Auto-recovery mechanisms"
echo "  • CloudWatch observability"
echo "  • System behavior under failure"
echo ""
echo -e "${CYAN}Scenarios:${NC}"
echo "  1. ECS Task Kill          (MEDIUM severity)"
echo "  2. RDS Failover           (MEDIUM severity)"
echo "  3. ElastiCache Flush      (MEDIUM severity)"
echo "  4. ALB Routing Failure    (HIGH severity)"
echo ""
echo -e "${YELLOW}⚠️  WARNING: This will impact your CloudCafe infrastructure${NC}"
echo -e "${YELLOW}    Make sure you have CloudWatch dashboard open!${NC}"
echo ""
read -p "Continue with master chaos experiment? (yes/no): " -r
echo

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    log_info "Master chaos experiment cancelled"
    exit 0
fi

# Track results
declare -A RESULTS
START_TIME=$(date +%s)

# Scenario 1: ECS Task Kill
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}SCENARIO 1: ECS Task Kill${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ -f "$SCENARIO_DIR/06-ecs-task-kill.sh" ]; then
    log_info "Executing: 06-ecs-task-kill.sh"
    if bash "$SCENARIO_DIR/06-ecs-task-kill.sh"; then
        RESULTS[ecs_task_kill]="SUCCESS"
        log_success "Scenario 1 completed"
    else
        RESULTS[ecs_task_kill]="FAILED"
        log_error "Scenario 1 failed"
    fi
else
    RESULTS[ecs_task_kill]="SKIPPED"
    log_warning "Scenario 1 script not found, skipping"
fi

log_info "Waiting ${PAUSE_BETWEEN_SCENARIOS}s before next scenario..."
sleep $PAUSE_BETWEEN_SCENARIOS

# Scenario 2: RDS Failover
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}SCENARIO 2: RDS Failover${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ -f "$SCENARIO_DIR/03-rds-failover.sh" ]; then
    log_info "Executing: 03-rds-failover.sh"
    if bash "$SCENARIO_DIR/03-rds-failover.sh"; then
        RESULTS[rds_failover]="SUCCESS"
        log_success "Scenario 2 completed"
    else
        RESULTS[rds_failover]="FAILED"
        log_error "Scenario 2 failed"
    fi
else
    RESULTS[rds_failover]="SKIPPED"
    log_warning "Scenario 2 script not found, skipping"
fi

log_info "Waiting ${PAUSE_BETWEEN_SCENARIOS}s before next scenario..."
sleep $PAUSE_BETWEEN_SCENARIOS

# Scenario 3: ElastiCache Flush
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}SCENARIO 3: ElastiCache Flush${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ -f "$SCENARIO_DIR/05-elasticache-flush.sh" ]; then
    log_info "Executing: 05-elasticache-flush.sh"
    if bash "$SCENARIO_DIR/05-elasticache-flush.sh"; then
        RESULTS[elasticache_flush]="SUCCESS"
        log_success "Scenario 3 completed"
    else
        RESULTS[elasticache_flush]="FAILED"
        log_error "Scenario 3 failed"
    fi
else
    RESULTS[elasticache_flush]="SKIPPED"
    log_warning "Scenario 3 script not found, skipping"
fi

log_info "Waiting ${PAUSE_BETWEEN_SCENARIOS}s before next scenario..."
sleep $PAUSE_BETWEEN_SCENARIOS

# Scenario 4: ALB Routing Failure
echo ""
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}SCENARIO 4: ALB Routing Failure (DESTRUCTIVE)${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}⚠️  This scenario will break ALB routing (HIGH severity)${NC}"
echo -e "${YELLOW}    Requires manual restoration via Terraform${NC}"
echo ""
read -p "Execute ALB routing failure scenario? (yes/no): " -r
echo

if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    if [ -f "$SCENARIO_DIR/01-alb-routing-failure.sh" ]; then
        log_info "Executing: 01-alb-routing-failure.sh"
        if bash "$SCENARIO_DIR/01-alb-routing-failure.sh"; then
            RESULTS[alb_routing_failure]="SUCCESS"
            log_success "Scenario 4 completed"
        else
            RESULTS[alb_routing_failure]="FAILED"
            log_error "Scenario 4 failed"
        fi
    else
        RESULTS[alb_routing_failure]="SKIPPED"
        log_warning "Scenario 4 script not found, skipping"
    fi
else
    RESULTS[alb_routing_failure]="SKIPPED"
    log_info "Scenario 4 skipped by user"
fi

# Summary
END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))

echo ""
echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${PURPLE}✅ MASTER CHAOS EXPERIMENT COMPLETE${NC}"
echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${CYAN}Results Summary:${NC}"
echo ""

SUCCESS_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

for scenario in "${!RESULTS[@]}"; do
    result="${RESULTS[$scenario]}"
    status_color=""

    case $result in
        SUCCESS)
            status_color=$GREEN
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            ;;
        FAILED)
            status_color=$RED
            FAILED_COUNT=$((FAILED_COUNT + 1))
            ;;
        SKIPPED)
            status_color=$YELLOW
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
            ;;
    esac

    echo -e "  ${scenario}: ${status_color}${result}${NC}"
done

echo ""
echo -e "${CYAN}Statistics:${NC}"
echo "  Total scenarios: ${#RESULTS[@]}"
echo -e "  ${GREEN}Successful: $SUCCESS_COUNT${NC}"
echo -e "  ${RED}Failed: $FAILED_COUNT${NC}"
echo -e "  ${YELLOW}Skipped: $SKIPPED_COUNT${NC}"
echo "  Total time: $((TOTAL_TIME / 60))m $((TOTAL_TIME % 60))s"
echo ""

echo -e "${CYAN}Next Steps:${NC}"
echo "  1. Review CloudWatch dashboard for anomalies"
echo "  2. Check all metrics recovered to normal"
echo "  3. If ALB routing was broken, restore with: terraform apply"
echo "  4. Document any unexpected behavior"
echo "  5. Update runbooks based on findings"
echo ""

log_success "Chaos engineering experiment complete!"
echo ""
