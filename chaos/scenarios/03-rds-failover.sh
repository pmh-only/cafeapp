#!/bin/bash
# Chaos Scenario: RDS Aurora Failover
#
# Story: The primary RDS Aurora instance experiences a hardware failure,
# triggering an automatic failover to the read replica. Applications
# experience a brief connection storm as they retry failed connections.
#
# Expected Impact:
# - 30-60 second downtime window
# - Connection errors spike
# - Database connection count spikes (connection storm)
# - Application 5XX errors during failover
# - Automatic recovery to new primary
#
# Duration: 60-90 seconds
# Severity: MEDIUM - Brief but complete database outage

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# Check prerequisites
check_aws_cli
check_terraform

# Configuration
SCENARIO_NAME="RDS Aurora Failover"
EXPECTED_IMPACT="30-60s database downtime, connection storm, app 5XX errors"
OBSERVATION_TIME=120

# Confirm chaos experiment
confirm_chaos "$SCENARIO_NAME" "$EXPECTED_IMPACT"

# Get RDS cluster ID from Terraform
log_info "Retrieving RDS cluster information from Terraform..."

CLUSTER_ID=$(get_terraform_output "rds_cluster_id")

if [ -z "$CLUSTER_ID" ]; then
    log_error "RDS cluster ID not found in Terraform outputs"
    log_info "Make sure you have deployed the infrastructure with 'terraform apply'"
    exit 1
fi

log_success "Found RDS cluster: $CLUSTER_ID"

# Check cluster status
log_info "Checking RDS cluster status..."

CLUSTER_STATUS=$(aws rds describe-db-clusters \
    --db-cluster-identifier "$CLUSTER_ID" \
    --query 'DBClusters[0].Status' \
    --output text)

if [ "$CLUSTER_STATUS" != "available" ]; then
    log_error "RDS cluster is not in 'available' state (current: $CLUSTER_STATUS)"
    log_info "Cannot perform failover on non-available cluster"
    exit 1
fi

log_success "Cluster status: $CLUSTER_STATUS"

# Get instance count
INSTANCE_COUNT=$(aws rds describe-db-clusters \
    --db-cluster-identifier "$CLUSTER_ID" \
    --query 'length(DBClusters[0].DBClusterMembers)' \
    --output text)

if [ "$INSTANCE_COUNT" -lt 2 ]; then
    log_error "RDS cluster has only $INSTANCE_COUNT instance(s)"
    log_info "Failover requires at least 2 instances (primary + replica)"
    exit 1
fi

log_success "Cluster has $INSTANCE_COUNT instances (failover supported)"

# Inject chaos
echo ""
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}🔥 INJECTING CHAOS: Triggering RDS Failover${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

log_warning "Initiating failover for cluster: $CLUSTER_ID"

aws rds failover-db-cluster \
    --db-cluster-identifier "$CLUSTER_ID" \
    --output json > /dev/null

log_success "✅ Chaos injected: RDS failover initiated"

# Display impact
echo ""
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}🔥 CHAOS ACTIVE: RDS Failover In Progress${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Expected CloudWatch Dashboard Indicators:${NC}"
echo "  • RDS Database Connections → Spike (connection storm)"
echo "  • Application 5XX Errors → Spike during failover"
echo "  • RDS CPU Utilization → Brief spike on new primary"
echo "  • Application Response Time → Spike during transition"
echo "  • ECS/Lambda Errors → Temporary increase"
echo ""
echo -e "${YELLOW}Failover Timeline:${NC}"
echo "  • T+0s:   Failover initiated"
echo "  • T+5s:   Old primary becomes unavailable"
echo "  • T+30s:  New primary promoted"
echo "  • T+45s:  DNS propagation begins"
echo "  • T+60s:  Applications reconnect successfully"
echo "  • T+90s:  Full stability restored"
echo ""
echo -e "${YELLOW}How to verify:${NC}"
echo "  1. Open CloudWatch dashboard"
echo "  2. Watch RDS connection count spike"
echo "  3. Watch application 5XX errors increase"
echo "  4. Monitor recovery as connections stabilize"
echo "  5. Check RDS console for new primary instance"
echo ""

wait_for_observation $OBSERVATION_TIME

# Check recovery
log_info "Checking failover completion..."

FINAL_STATUS=$(aws rds describe-db-clusters \
    --db-cluster-identifier "$CLUSTER_ID" \
    --query 'DBClusters[0].Status' \
    --output text)

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}RECOVERY STATUS${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Cluster status: $FINAL_STATUS"
echo ""

if [ "$FINAL_STATUS" == "available" ]; then
    log_success "✅ Failover complete! Cluster is available on new primary."

    # Show new primary
    NEW_PRIMARY=$(aws rds describe-db-clusters \
        --db-cluster-identifier "$CLUSTER_ID" \
        --query 'DBClusters[0].DBClusterMembers[?IsClusterWriter==`true`].DBInstanceIdentifier' \
        --output text)

    log_info "New primary instance: $NEW_PRIMARY"
else
    log_warning "⏳ Failover still in progress (status: $FINAL_STATUS)"
    log_info "Wait a few more minutes for cluster to stabilize"
fi

echo ""
log_info "No manual restoration needed - Aurora handles failover automatically"
echo ""
