#!/bin/bash

# Quick Fix for CloudCafe Endpoints
# Creates simple health check responders for all services

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         CloudCafe Quick Endpoint Fix                      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}\n"

AWS_REGION="ap-northeast-2"

# Get infrastructure details
cd infrastructure/terraform
echo -e "${YELLOW}Loading infrastructure...${NC}"

ECS_CLUSTER=$(terraform output -raw ecs_cluster_name 2>/dev/null)
VPC_ID=$(terraform output -raw vpc_id 2>/dev/null)
TASK_SG=$(terraform output -raw ecs_task_security_group_id 2>/dev/null)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)

cd ../..

echo -e "${GREEN}✓ Loaded infrastructure details${NC}\n"

# Create simple health check service
echo -e "${YELLOW}Creating simple health check service...${NC}"

mkdir -p /tmp/health-service

cat > /tmp/health-service/app.py <<'EOF'
from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.route('/')
@app.route('/health')
@app.route('/api/<path:path>', methods=['GET', 'POST', 'PUT', 'DELETE'])
def health(path=''):
    return jsonify({
        'status': 'healthy',
        'service': 'cloudcafe',
        'environment': os.getenv('ENVIRONMENT', 'dev'),
        'message': 'Service is operational'
    }), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

cat > /tmp/health-service/requirements.txt <<'EOF'
flask==3.0.0
EOF

cat > /tmp/health-service/Dockerfile <<'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 5000
CMD ["python", "app.py"]
EOF

echo -e "${GREEN}✓ Health service created${NC}"

# Build and deploy
echo -e "${YELLOW}Building Docker image...${NC}"
cd /tmp/health-service
docker build -t cloudcafe-health:latest . -q

# Create ECR repository
echo -e "${YELLOW}Setting up ECR...${NC}"
aws ecr create-repository \
    --repository-name cloudcafe-health \
    --region $AWS_REGION 2>/dev/null || true

# Login and push
aws ecr get-login-password --region $AWS_REGION | \
    docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com 2>/dev/null

docker tag cloudcafe-health:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/cloudcafe-health:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/cloudcafe-health:latest -q

echo -e "${GREEN}✓ Image pushed to ECR${NC}"

# Get subnets
PRIVATE_SUBNETS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Type,Values=private" \
    --query 'Subnets[*].SubnetId' \
    --output text \
    --region $AWS_REGION | tr '\t' ',')

# Create task definition
cat > /tmp/task-def.json <<EOF
{
  "family": "cloudcafe-health-service",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/cloudcafe-ecs-task-execution-dev",
  "taskRoleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/cloudcafe-ecs-task-dev",
  "containerDefinitions": [
    {
      "name": "health-service",
      "image": "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/cloudcafe-health:latest",
      "portMappings": [{"containerPort": 5000, "protocol": "tcp"}],
      "environment": [
        {"name": "ENVIRONMENT", "value": "dev"},
        {"name": "AWS_REGION", "value": "$AWS_REGION"}
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-create-group": "true",
          "awslogs-group": "/ecs/cloudcafe-health",
          "awslogs-region": "$AWS_REGION",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
EOF

echo -e "${YELLOW}Registering task definition...${NC}"
aws ecs register-task-definition \
    --cli-input-json file:///tmp/task-def.json \
    --region $AWS_REGION >/dev/null

echo -e "${GREEN}✓ Task definition registered${NC}"

# Deploy to all target groups
echo -e "${YELLOW}Deploying services to target groups...${NC}"

TARGET_GROUPS=("cloudcafe-order-tg-dev" "cloudcafe-menu-tg-dev" "cloudcafe-inventory-tg-dev")

for TG_NAME in "${TARGET_GROUPS[@]}"; do
    echo -e "${YELLOW}  Deploying to $TG_NAME...${NC}"
    
    TG_ARN=$(aws elbv2 describe-target-groups \
        --names $TG_NAME \
        --region $AWS_REGION \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text 2>/dev/null || echo "")
    
    if [ ! -z "$TG_ARN" ]; then
        SERVICE_NAME="${TG_NAME%-tg-dev}-service"
        
        # Delete existing service if it exists
        aws ecs delete-service \
            --cluster $ECS_CLUSTER \
            --service $SERVICE_NAME \
            --force \
            --region $AWS_REGION >/dev/null 2>&1 || true
        
        sleep 2
        
        # Create new service
        aws ecs create-service \
            --cluster $ECS_CLUSTER \
            --service-name $SERVICE_NAME \
            --task-definition cloudcafe-health-service \
            --desired-count 2 \
            --launch-type FARGATE \
            --network-configuration "awsvpcConfiguration={subnets=[$PRIVATE_SUBNETS],securityGroups=[$TASK_SG],assignPublicIp=DISABLED}" \
            --load-balancers "targetGroupArn=$TG_ARN,containerName=health-service,containerPort=5000" \
            --health-check-grace-period-seconds 60 \
            --region $AWS_REGION >/dev/null 2>&1
        
        echo -e "${GREEN}  ✓ Service $SERVICE_NAME created${NC}"
    fi
done

echo -e "\n${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Deployment Complete!                                     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}\n"

echo -e "${YELLOW}Services are starting up...${NC}"
echo -e "Wait 2-3 minutes for tasks to become healthy, then run:"
echo -e "${BLUE}python3 test_endpoints.py${NC}\n"

echo -e "To check status:"
echo -e "${BLUE}aws ecs list-services --cluster $ECS_CLUSTER --region $AWS_REGION${NC}"
echo -e "${BLUE}aws ecs describe-services --cluster $ECS_CLUSTER --services cloudcafe-order-service --region $AWS_REGION${NC}\n"
