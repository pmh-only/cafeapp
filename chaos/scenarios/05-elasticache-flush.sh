#!/bin/bash
# Chaos Scenario: ElastiCache Flush
#
# Story: A cache cluster restart or maintenance window flushes all cached data.
# Applications experience a cache miss storm, causing a massive spike in
# database queries as they rebuild the cache from scratch.
#
# Expected Impact:
# - Cache hit rate drops to 0%
# - Database (RDS/DocumentDB) query count spikes 10-100x
# - Application response time increases significantly
# - Database CPU utilization spikes
# - Gradual recovery as cache repopulates
#
# Duration: 5-10 minutes for cache to warm up
# Severity: MEDIUM - Degraded performance, possible timeouts

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# Check prerequisites
check_required_tools aws redis-cli

check_terraform

# Configuration
SCENARIO_NAME="ElastiCache Flush (Cache Miss Storm)"
EXPECTED_IMPACT="Cache hit rate → 0%, database query storm, slower response times"
OBSERVATION_TIME=90

# Confirm chaos experiment
confirm_chaos "$SCENARIO_NAME" "$EXPECTED_IMPACT"

# Get ElastiCache endpoint from Terraform
log_info "Retrieving ElastiCache information from Terraform..."

CACHE_ENDPOINT=$(get_terraform_output "elasticache_endpoint")

if [ -z "$CACHE_ENDPOINT" ]; then
    log_error "ElastiCache endpoint not found in Terraform outputs"
    log_info "Make sure you have deployed the infrastructure with 'terraform apply'"
    exit 1
fi

log_success "Found ElastiCache endpoint: $CACHE_ENDPOINT"

# Get cluster ID
CLUSTER_ID=$(get_terraform_output "elasticache_cluster_id")
log_info "Cluster ID: $CLUSTER_ID"

# Test connectivity
log_info "Testing Redis connectivity..."

if redis-cli -h "$CACHE_ENDPOINT" PING > /dev/null 2>&1; then
    log_success "Successfully connected to Redis"
else
    log_error "Cannot connect to Redis at $CACHE_ENDPOINT"
    log_info "Make sure:"
    log_info "  1. You're running from a machine with access to the VPC"
    log_info "  2. Security groups allow Redis access"
    log_info "  3. You have redis-cli installed"
    exit 1
fi

# Get cache statistics before flush
log_info "Collecting pre-flush statistics..."

KEYSPACE_BEFORE=$(redis-cli -h "$CACHE_ENDPOINT" INFO keyspace | grep db0 || echo "db0:keys=0")
STATS_BEFORE=$(redis-cli -h "$CACHE_ENDPOINT" INFO stats)

log_info "Cache state before flush:"
echo "$KEYSPACE_BEFORE"

# Inject chaos
echo ""
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}🔥 INJECTING CHAOS: Flushing ElastiCache${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

log_warning "Flushing all data from Redis..."

FLUSH_RESULT=$(redis-cli -h "$CACHE_ENDPOINT" FLUSHALL)

if [ "$FLUSH_RESULT" == "OK" ]; then
    log_success "✅ Chaos injected: ElastiCache flushed successfully"
else
    log_error "Flush command failed: $FLUSH_RESULT"
    exit 1
fi

# Verify flush
KEYSPACE_AFTER=$(redis-cli -h "$CACHE_ENDPOINT" INFO keyspace | grep db0 || echo "db0:keys=0")
log_info "Cache state after flush:"
echo "$KEYSPACE_AFTER"

# Display impact
echo ""
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}🔥 CHAOS ACTIVE: Cache Miss Storm${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Expected CloudWatch Dashboard Indicators:${NC}"
echo "  • ElastiCache Hit Rate → Drops to 0%"
echo "  • ElastiCache Cache Misses → Spikes dramatically"
echo "  • RDS Database Connections → Increases significantly"
echo "  • DocumentDB CPU Utilization → Spikes (more queries)"
echo "  • Application Response Time → Increases (slower without cache)"
echo "  • Application 5XX Errors → May increase if DB overwhelmed"
echo ""
echo -e "${YELLOW}Recovery Timeline:${NC}"
echo "  • T+0s:    Cache flushed, hit rate = 0%"
echo "  • T+30s:   Applications start repopulating cache"
echo "  • T+120s:  Frequently accessed data cached"
echo "  • T+300s:  Hit rate recovers to ~50%"
echo "  • T+600s:  Hit rate stabilizes at normal levels (70-90%)"
echo ""
echo -e "${YELLOW}Database Impact:${NC}"
echo "  • Menu Service → DocumentDB query spike for menu items"
echo "  • Order Service → RDS query spike for order lookups"
echo "  • Each cache miss = 1 database query"
echo "  • May cause database connection pool exhaustion"
echo ""
echo -e "${YELLOW}How to verify:${NC}"
echo "  1. Open CloudWatch dashboard"
echo "  2. Watch ElastiCache hit rate drop to 0%"
echo "  3. Watch database connection count increase"
echo "  4. Watch application response time increase"
echo "  5. Monitor gradual recovery as cache warms up"
echo ""

# Real-time monitoring
log_info "Monitoring cache recovery..."

for i in {1..6}; do
    sleep 15

    CURRENT_KEYS=$(redis-cli -h "$CACHE_ENDPOINT" DBSIZE)
    CURRENT_STATS=$(redis-cli -h "$CACHE_ENDPOINT" INFO stats | grep keyspace)

    echo "[$((i*15))s] Cache keys: $CURRENT_KEYS"
done

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}RECOVERY STATUS${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

FINAL_KEYS=$(redis-cli -h "$CACHE_ENDPOINT" DBSIZE)
log_info "Current cache keys: $FINAL_KEYS"

if [ "$FINAL_KEYS" -gt 0 ]; then
    log_success "✅ Cache is repopulating (applications are rebuilding cache)"
else
    log_warning "⏳ Cache still empty (may indicate low traffic or caching disabled)"
fi

echo ""
log_info "No manual restoration needed - cache will repopulate automatically"
log_info "Full recovery may take 5-10 minutes depending on traffic patterns"
echo ""
