#!/bin/bash
# Chaos Scenario: DynamoDB Throttling
#
# Story: An unexpected traffic spike (viral social media post, flash sale)
# causes API requests to spike 10x. The DynamoDB tables, configured with
# low provisioned capacity, begin throttling requests, causing application
# errors and increased latency.
#
# Expected Impact:
# - DynamoDB UserErrors metric spikes (throttled requests)
# - Application 5XX errors increase
# - Response time increases significantly
# - Lambda invocations may fail (if SQS/Kinesis backed)
# - Automatic DynamoDB auto-scaling kicks in (if enabled)
#
# Duration: 5-10 minutes (depending on auto-scaling)
# Severity: HIGH - Data access failures

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# Check prerequisites
check_aws_cli
check_terraform

# Configuration
SCENARIO_NAME="DynamoDB Throttling (Capacity Reduction)"
EXPECTED_IMPACT="Throttled requests spike, 5XX errors, Lambda failures"
OBSERVATION_TIME=120

# Confirm chaos experiment
confirm_chaos "$SCENARIO_NAME" "$EXPECTED_IMPACT"

# Get DynamoDB table names from Terraform
log_info "Retrieving DynamoDB table information from Terraform..."

# For this demo, we'll throttle the active-orders table
TABLE_NAME="cloudcafe-active-orders-dev"

# Check if table exists
TABLE_STATUS=$(aws dynamodb describe-table \
    --table-name "$TABLE_NAME" \
    --query 'Table.TableStatus' \
    --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$TABLE_STATUS" == "NOT_FOUND" ]; then
    log_error "DynamoDB table '$TABLE_NAME' not found"
    log_info "Make sure infrastructure is deployed with 'terraform apply'"
    exit 1
fi

log_success "Found table: $TABLE_NAME (Status: $TABLE_STATUS)"

# Get current billing mode
BILLING_MODE=$(aws dynamodb describe-table \
    --table-name "$TABLE_NAME" \
    --query 'Table.BillingModeSummary.BillingMode' \
    --output text 2>/dev/null || echo "PROVISIONED")

if [ "$BILLING_MODE" == "PAY_PER_REQUEST" ]; then
    log_warning "Table is in PAY_PER_REQUEST mode (on-demand)"
    log_info "Converting to PROVISIONED mode for throttling simulation..."

    # Backup current configuration
    BACKUP_DIR=$(create_backup_dir)
    aws dynamodb describe-table --table-name "$TABLE_NAME" > "$BACKUP_DIR/dynamodb_${TABLE_NAME}_backup.json"

    # Convert to provisioned mode with low capacity
    aws dynamodb update-table \
        --table-name "$TABLE_NAME" \
        --billing-mode PROVISIONED \
        --provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1 \
        --output json > /dev/null

    log_info "Waiting for table update to complete..."
    aws dynamodb wait table-exists --table-name "$TABLE_NAME"
    sleep 10
else
    # Already provisioned, just reduce capacity
    BACKUP_DIR=$(create_backup_dir)
    aws dynamodb describe-table --table-name "$TABLE_NAME" > "$BACKUP_DIR/dynamodb_${TABLE_NAME}_backup.json"

    CURRENT_READ=$(aws dynamodb describe-table \
        --table-name "$TABLE_NAME" \
        --query 'Table.ProvisionedThroughput.ReadCapacityUnits' \
        --output text)

    CURRENT_WRITE=$(aws dynamodb describe-table \
        --table-name "$TABLE_NAME" \
        --query 'Table.ProvisionedThroughput.WriteCapacityUnits' \
        --output text)

    log_info "Current capacity: Read=$CURRENT_READ WCU, Write=$CURRENT_WRITE WCU"
fi

# Inject chaos - set to minimal capacity
echo ""
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}🔥 INJECTING CHAOS: Throttling DynamoDB${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

log_warning "Reducing DynamoDB capacity to trigger throttling..."

aws dynamodb update-table \
    --table-name "$TABLE_NAME" \
    --provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1 \
    --output json > /dev/null

log_success "✅ Chaos injected: DynamoDB throttled to 1 RCU / 1 WCU"

log_info "Waiting for capacity change to take effect..."
aws dynamodb wait table-exists --table-name "$TABLE_NAME"
sleep 5

# Verify new capacity
NEW_READ=$(aws dynamodb describe-table \
    --table-name "$TABLE_NAME" \
    --query 'Table.ProvisionedThroughput.ReadCapacityUnits' \
    --output text)

NEW_WRITE=$(aws dynamodb describe-table \
    --table-name "$TABLE_NAME" \
    --query 'Table.ProvisionedThroughput.WriteCapacityUnits' \
    --output text)

log_info "New capacity: Read=$NEW_READ RCU, Write=$NEW_WRITE WCU"

# Display impact
echo ""
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}🔥 CHAOS ACTIVE: DynamoDB Throttling${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Expected CloudWatch Dashboard Indicators:${NC}"
echo "  • DynamoDB UserErrors → Spikes dramatically"
echo "  • DynamoDB ThrottledRequests → Increases to 100s/sec"
echo "  • Application 5XX Errors → Increases (DB write failures)"
echo "  • Lambda Errors → Spikes (if using DynamoDB triggers)"
echo "  • Response Time → Increases 2-5x"
echo ""
echo -e "${YELLOW}Impact by Service:${NC}"
echo "  • Order Service → Cannot write new orders (5XX errors)"
echo "  • Inventory Service → Read queries throttled"
echo "  • Payment Processor → DynamoDB writes fail"
echo ""
echo -e "${YELLOW}Recovery Options:${NC}"
echo "  • Auto-scaling (if enabled): 5-10 minutes"
echo "  • Manual capacity increase: Immediate"
echo "  • Switch to on-demand billing: 2-3 minutes"
echo ""
echo -e "${YELLOW}How to verify:${NC}"
echo "  1. Open CloudWatch dashboard"
echo "  2. Watch DynamoDB UserErrors metric spike"
echo "  3. Try creating an order (should fail or be very slow)"
echo "  4. Check application logs for 'ProvisionedThroughputExceededException'"
echo ""

# Monitor throttling
log_info "Monitoring DynamoDB throttling..."

for i in {1..6}; do
    sleep 20

    # Get throttle metrics
    END_TIME=$(date -u +%Y-%m-%dT%H:%M:%S)
    START_TIME=$(date -u -d '1 minute ago' +%Y-%m-%dT%H:%M:%S)

    THROTTLED=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/DynamoDB \
        --metric-name UserErrors \
        --dimensions Name=TableName,Value=$TABLE_NAME \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --period 60 \
        --statistics Sum \
        --query 'Datapoints[0].Sum' \
        --output text 2>/dev/null || echo "0")

    if [ "$THROTTLED" == "None" ]; then
        THROTTLED=0
    fi

    echo "[$((i*20))s] Throttled requests (last minute): $THROTTLED"
done

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}RESTORE INSTRUCTIONS${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Option 1: Restore to on-demand billing (recommended):"
echo "  aws dynamodb update-table \\"
echo "    --table-name $TABLE_NAME \\"
echo "    --billing-mode PAY_PER_REQUEST"
echo ""
echo "Option 2: Increase provisioned capacity:"
echo "  aws dynamodb update-table \\"
echo "    --table-name $TABLE_NAME \\"
echo "    --provisioned-throughput ReadCapacityUnits=50,WriteCapacityUnits=50"
echo ""
echo "Option 3: Re-run Terraform (restores original config):"
echo "  cd ../../infrastructure/terraform"
echo "  terraform apply"
echo ""
log_warning "Table is currently throttled (1 RCU / 1 WCU)"
log_info "Application write operations will fail until capacity is restored"
echo ""
