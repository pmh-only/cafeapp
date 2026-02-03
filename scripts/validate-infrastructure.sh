#!/bin/bash
# Infrastructure Validation Script
#
# Validates that all AWS services are deployed correctly and emitting
# CloudWatch metrics as expected.

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# Check functions
check_service() {
    local service_name=$1
    local check_command=$2

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    echo -n "  Checking $service_name... "

    if eval "$check_command" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        echo -e "${RED}✗${NC}"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

check_metric() {
    local namespace=$1
    local metric_name=$2
    local dimensions=$3

    local end_time=$(date -u +%Y-%m-%dT%H:%M:%S)
    local start_time=$(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S)

    local result=$(aws cloudwatch get-metric-statistics \
        --namespace "$namespace" \
        --metric-name "$metric_name" \
        ${dimensions:+--dimensions $dimensions} \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --period 300 \
        --statistics Average \
        --query 'Datapoints' \
        --output json)

    if [ "$result" != "[]" ]; then
        return 0
    else
        return 1
    fi
}

# Banner
clear
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}CloudCafe Infrastructure Validation${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Get Terraform outputs
echo -e "${YELLOW}Retrieving infrastructure information...${NC}"
cd "$(dirname "$0")/../infrastructure/terraform"

VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "")
ECS_CLUSTER_NAME=$(terraform output -raw ecs_cluster_name 2>/dev/null || echo "")
EKS_CLUSTER_NAME=$(terraform output -raw eks_cluster_name 2>/dev/null || echo "")
RDS_CLUSTER_ID=$(terraform output -raw rds_cluster_id 2>/dev/null || echo "")

cd - > /dev/null

if [ -z "$VPC_ID" ]; then
    echo -e "${RED}Error: Infrastructure not deployed. Run 'terraform apply' first.${NC}"
    exit 1
fi

echo -e "${GREEN}Infrastructure found!${NC}"
echo ""

# 1. Network Infrastructure
echo -e "${BLUE}━━━ Network Infrastructure ━━━${NC}"
check_service "VPC" "aws ec2 describe-vpcs --vpc-ids $VPC_ID"
check_service "Subnets" "aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC_ID --query 'Subnets[0]'"
check_service "Security Groups" "aws ec2 describe-security-groups --filters Name=vpc-id,Values=$VPC_ID --query 'SecurityGroups[0]'"
echo ""

# 2. Compute Services
echo -e "${BLUE}━━━ Compute Services ━━━${NC}"

if [ -n "$ECS_CLUSTER_NAME" ]; then
    check_service "ECS Cluster" "aws ecs describe-clusters --clusters $ECS_CLUSTER_NAME --query 'clusters[0].clusterArn'"
    check_service "ECS Metrics" "check_metric 'AWS/ECS' 'CPUUtilization' 'Name=ClusterName,Value=$ECS_CLUSTER_NAME'"
fi

if [ -n "$EKS_CLUSTER_NAME" ]; then
    check_service "EKS Cluster" "aws eks describe-cluster --name $EKS_CLUSTER_NAME --query 'cluster.arn'"
    check_service "EKS Node Group" "aws eks list-nodegroups --cluster-name $EKS_CLUSTER_NAME --query 'nodegroups[0]'"
fi

check_service "EC2 Auto Scaling Groups" "aws autoscaling describe-auto-scaling-groups --query 'AutoScalingGroups[?contains(AutoScalingGroupName, \`cloudcafe\`)].AutoScalingGroupName' --output text"
echo ""

# 3. Database Services
echo -e "${BLUE}━━━ Database Services ━━━${NC}"

if [ -n "$RDS_CLUSTER_ID" ]; then
    check_service "RDS Aurora" "aws rds describe-db-clusters --db-cluster-identifier $RDS_CLUSTER_ID --query 'DBClusters[0].Status'"
    check_service "RDS Metrics" "check_metric 'AWS/RDS' 'DatabaseConnections' 'Name=DBClusterIdentifier,Value=$RDS_CLUSTER_ID'"
fi

check_service "DynamoDB Tables" "aws dynamodb list-tables --query 'TableNames[?contains(@, \`cloudcafe\`)]' --output text"
check_service "DynamoDB Metrics" "check_metric 'AWS/DynamoDB' 'UserErrors'"

check_service "DocumentDB Cluster" "aws docdb describe-db-clusters --query 'DBClusters[?contains(DBClusterIdentifier, \`cloudcafe\`)].DBClusterIdentifier' --output text"

check_service "Redshift Cluster" "aws redshift describe-clusters --query 'Clusters[?contains(ClusterIdentifier, \`cloudcafe\`)].ClusterIdentifier' --output text"
echo ""

# 4. Caching Services
echo -e "${BLUE}━━━ Caching Services ━━━${NC}"
check_service "ElastiCache" "aws elasticache describe-cache-clusters --query 'CacheClusters[?contains(CacheClusterId, \`cloudcafe\`)].CacheClusterId' --output text"
check_service "ElastiCache Metrics" "check_metric 'AWS/ElastiCache' 'CPUUtilization'"

check_service "MemoryDB" "aws memorydb describe-clusters --query 'Clusters[?contains(Name, \`cloudcafe\`)].Name' --output text"
echo ""

# 5. Messaging Services
echo -e "${BLUE}━━━ Messaging Services ━━━${NC}"
check_service "SQS Queues" "aws sqs list-queues --queue-name-prefix cloudcafe --query 'QueueUrls[0]'"
check_service "SQS Metrics" "check_metric 'AWS/SQS' 'NumberOfMessagesSent'"

check_service "Kinesis Streams" "aws kinesis list-streams --query 'StreamNames[?contains(@, \`cloudcafe\`)]' --output text"
check_service "Kinesis Metrics" "check_metric 'AWS/Kinesis' 'IncomingRecords'"
echo ""

# 6. Serverless Services
echo -e "${BLUE}━━━ Serverless Services ━━━${NC}"
check_service "Lambda Functions" "aws lambda list-functions --query 'Functions[?contains(FunctionName, \`cloudcafe\`)].FunctionName' --output text"
check_service "API Gateway" "aws apigateway get-rest-apis --query 'items[?contains(name, \`cloudcafe\`)].id' --output text"
echo ""

# 7. Load Balancing & CDN
echo -e "${BLUE}━━━ Load Balancing & CDN ━━━${NC}"
check_service "Application Load Balancers" "aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, \`cloudcafe\`)].LoadBalancerArn' --output text"
check_service "ALB Metrics" "check_metric 'AWS/ApplicationELB' 'RequestCount'"

check_service "Network Load Balancers" "aws elbv2 describe-load-balancers --query 'LoadBalancers[?Type==\`network\` && contains(LoadBalancerName, \`cloudcafe\`)].LoadBalancerArn' --output text"

check_service "CloudFront Distributions" "aws cloudfront list-distributions --query 'DistributionList.Items[?Comment && contains(Comment, \`cloudcafe\`)].Id' --output text"
echo ""

# Summary
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Validation Summary${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Total checks: $TOTAL_CHECKS"
echo -e "  ${GREEN}Passed: $PASSED_CHECKS${NC}"
echo -e "  ${RED}Failed: $FAILED_CHECKS${NC}"
echo ""

if [ $FAILED_CHECKS -eq 0 ]; then
    echo -e "${GREEN}✅ All validation checks passed!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Open CloudWatch dashboard to view metrics"
    echo "  2. Run load tests: cd load-testing && k6 run k6/scenarios/morning-rush.js"
    echo "  3. Execute chaos scenarios: cd chaos && ./master-chaos.sh"
    echo ""
    exit 0
else
    echo -e "${YELLOW}⚠️  Some validation checks failed.${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Ensure infrastructure is fully deployed: terraform apply"
    echo "  2. Wait 5-10 minutes for metrics to appear in CloudWatch"
    echo "  3. Check that services are running and healthy"
    echo "  4. Verify AWS credentials and region are correct"
    echo ""
    exit 1
fi
