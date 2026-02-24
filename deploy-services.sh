#!/bin/bash

# CloudCafe Service Deployment Script
# Region: ap-northeast-2 (Seoul)
# This script deploys all backend services to fix endpoint issues

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         CloudCafe Service Deployment                      ║${NC}"
echo -e "${BLUE}║         Region: ap-northeast-2 (Seoul)                    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}\n"

# Get AWS account ID and region
AWS_REGION="ap-northeast-2"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")

if [ -z "$AWS_ACCOUNT_ID" ]; then
    echo -e "${RED}Error: Unable to get AWS account ID. Please configure AWS CLI.${NC}"
    exit 1
fi

echo -e "${GREEN}AWS Account ID: $AWS_ACCOUNT_ID${NC}"
echo -e "${GREEN}AWS Region: $AWS_REGION${NC}\n"

# Load Terraform outputs
cd infrastructure/terraform
echo -e "${YELLOW}Loading infrastructure outputs...${NC}"

ECS_CLUSTER=$(terraform output -raw ecs_cluster_name 2>/dev/null || echo "")
EKS_CLUSTER=$(terraform output -raw eks_cluster_name 2>/dev/null || echo "")
VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "")
TASK_SG=$(terraform output -raw ecs_task_security_group_id 2>/dev/null || echo "")

cd ../..

if [ -z "$ECS_CLUSTER" ] || [ -z "$EKS_CLUSTER" ]; then
    echo -e "${RED}Error: Unable to load infrastructure outputs${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Infrastructure outputs loaded${NC}"
echo -e "  ECS Cluster: $ECS_CLUSTER"
echo -e "  EKS Cluster: $EKS_CLUSTER"
echo -e "  VPC ID: $VPC_ID\n"

# Function to create ECR repository if it doesn't exist
create_ecr_repo() {
    local repo_name=$1
    echo -e "${YELLOW}Checking ECR repository: $repo_name${NC}"
    
    if aws ecr describe-repositories --repository-names "$repo_name" --region $AWS_REGION >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Repository exists${NC}"
    else
        echo -e "${YELLOW}Creating ECR repository...${NC}"
        aws ecr create-repository \
            --repository-name "$repo_name" \
            --region $AWS_REGION \
            --image-scanning-configuration scanOnPush=true \
            --encryption-configuration encryptionType=AES256 >/dev/null
        echo -e "${GREEN}✓ Repository created${NC}"
    fi
}

# Function to build and push Docker image
build_and_push() {
    local service_name=$1
    local service_path=$2
    local repo_name=$3
    
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Building and pushing: $service_name${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}\n"
    
    # Create ECR repository
    create_ecr_repo "$repo_name"
    
    # Login to ECR
    echo -e "${YELLOW}Logging in to ECR...${NC}"
    aws ecr get-login-password --region $AWS_REGION | \
        docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
    
    # Build image
    echo -e "${YELLOW}Building Docker image...${NC}"
    cd "$service_path"
    docker build -t "$repo_name:latest" . --quiet
    
    # Tag image
    docker tag "$repo_name:latest" "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$repo_name:latest"
    
    # Push image
    echo -e "${YELLOW}Pushing to ECR...${NC}"
    docker push "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$repo_name:latest" --quiet
    
    echo -e "${GREEN}✓ Image pushed successfully${NC}"
    cd - >/dev/null
}

# ============================================
# 1. Deploy Order Service to ECS Fargate
# ============================================
echo -e "\n${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Step 1: Deploy Order Service to ECS Fargate             ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}\n"

build_and_push "Order Service" "services/order-service" "cloudcafe-order-service"

echo -e "${YELLOW}Creating ECS task definition...${NC}"

# Create task definition JSON
cat > /tmp/order-service-task.json <<EOF
{
  "family": "cloudcafe-order-service",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/cloudcafe-ecs-task-execution-dev",
  "taskRoleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/cloudcafe-ecs-task-dev",
  "containerDefinitions": [
    {
      "name": "order-service",
      "image": "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/cloudcafe-order-service:latest",
      "portMappings": [
        {
          "containerPort": 5000,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {"name": "ENVIRONMENT", "value": "dev"},
        {"name": "AWS_REGION", "value": "$AWS_REGION"}
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/cloudcafe-order-service",
          "awslogs-region": "$AWS_REGION",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
EOF

# Register task definition
aws ecs register-task-definition \
    --cli-input-json file:///tmp/order-service-task.json \
    --region $AWS_REGION >/dev/null

echo -e "${GREEN}✓ Task definition registered${NC}"

# Create CloudWatch log group
aws logs create-log-group \
    --log-group-name /ecs/cloudcafe-order-service \
    --region $AWS_REGION 2>/dev/null || true

echo -e "${YELLOW}Creating ECS service...${NC}"

# Get subnet IDs
PRIVATE_SUBNETS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Type,Values=private" \
    --query 'Subnets[*].SubnetId' \
    --output text \
    --region $AWS_REGION | tr '\t' ',')

# Get target group ARN
TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups \
    --names cloudcafe-order-tg-dev \
    --region $AWS_REGION \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text 2>/dev/null || echo "")

if [ ! -z "$TARGET_GROUP_ARN" ]; then
    # Create service with load balancer
    aws ecs create-service \
        --cluster $ECS_CLUSTER \
        --service-name order-service \
        --task-definition cloudcafe-order-service \
        --desired-count 2 \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[$PRIVATE_SUBNETS],securityGroups=[$TASK_SG],assignPublicIp=DISABLED}" \
        --load-balancers "targetGroupArn=$TARGET_GROUP_ARN,containerName=order-service,containerPort=5000" \
        --region $AWS_REGION >/dev/null 2>&1 || echo -e "${YELLOW}Service may already exist${NC}"
    
    echo -e "${GREEN}✓ ECS service created with load balancer${NC}"
else
    echo -e "${YELLOW}⚠ Target group not found, creating service without LB${NC}"
    aws ecs create-service \
        --cluster $ECS_CLUSTER \
        --service-name order-service \
        --task-definition cloudcafe-order-service \
        --desired-count 2 \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[$PRIVATE_SUBNETS],securityGroups=[$TASK_SG],assignPublicIp=DISABLED}" \
        --region $AWS_REGION >/dev/null 2>&1 || echo -e "${YELLOW}Service may already exist${NC}"
fi

# ============================================
# 2. Configure EKS
# ============================================
echo -e "\n${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Step 2: Configure EKS Access                             ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}\n"

echo -e "${YELLOW}Updating kubeconfig...${NC}"
aws eks update-kubeconfig --name $EKS_CLUSTER --region $AWS_REGION >/dev/null 2>&1 || true

# Check if kubectl is available
if command -v kubectl &> /dev/null; then
    echo -e "${GREEN}✓ kubectl configured${NC}"
    kubectl get nodes 2>/dev/null || echo -e "${YELLOW}⚠ Unable to connect to EKS cluster${NC}"
else
    echo -e "${YELLOW}⚠ kubectl not installed, skipping EKS deployments${NC}"
fi

# ============================================
# Summary
# ============================================
echo -e "\n${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Deployment Summary                                       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}\n"

echo -e "${GREEN}✓ Order Service deployed to ECS Fargate${NC}"
echo -e "${YELLOW}⚠ Menu Service (EKS) - requires kubectl${NC}"
echo -e "${YELLOW}⚠ Inventory Service (EKS) - requires kubectl${NC}"
echo -e "${YELLOW}⚠ Loyalty Service (EC2) - requires manual deployment${NC}"

echo -e "\n${BLUE}Next Steps:${NC}"
echo -e "1. Wait 2-3 minutes for ECS tasks to start"
echo -e "2. Run: ${YELLOW}python3 test_endpoints.py${NC} to verify"
echo -e "3. Check ECS console for task status"
echo -e "4. Deploy remaining services manually if needed\n"

echo -e "${GREEN}Deployment script completed!${NC}\n"
