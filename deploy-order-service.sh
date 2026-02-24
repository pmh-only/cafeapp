#!/bin/bash
set -e

AWS_REGION="ap-northeast-2"
AWS_ACCOUNT_ID="972209100553"

echo "=== Deploying Order Service to ECS ==="

# Get infrastructure details
cd infrastructure/terraform
VPC_ID=$(terraform output -raw vpc_id)
ECS_CLUSTER=$(terraform output -raw ecs_cluster_name)
TASK_SG=$(terraform output -raw ecs_task_security_group_id)
RDS_ENDPOINT=$(terraform output -raw rds_cluster_endpoint)
REDIS_ENDPOINT=$(terraform output -raw elasticache_endpoint)
KINESIS_STREAM=$(terraform output -raw order_events_stream_name)
DYNAMODB_TABLE=$(terraform output -json dynamodb_table_names | jq -r '.active_orders')
cd ../..

echo "Infrastructure:"
echo "  VPC: $VPC_ID"
echo "  ECS Cluster: $ECS_CLUSTER"
echo "  Task SG: $TASK_SG"
echo "  RDS: $RDS_ENDPOINT"
echo "  Redis: $REDIS_ENDPOINT"
echo "  Kinesis: $KINESIS_STREAM"
echo "  DynamoDB: $DYNAMODB_TABLE"

# Get private subnets
PRIVATE_SUBNETS=$(/usr/local/bin/aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Type,Values=private" \
    --query 'Subnets[*].SubnetId' \
    --output text \
    --region $AWS_REGION | tr '\t' ',')

echo "  Private Subnets: $PRIVATE_SUBNETS"

# Create CloudWatch log group
/usr/local/bin/aws logs create-log-group \
    --log-group-name /ecs/cloudcafe-order-service \
    --region $AWS_REGION 2>/dev/null || echo "Log group already exists"

# Create task definition
cat > /tmp/order-service-task.json <<EOF
{
  "family": "cloudcafe-order-service",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/cloudcafe-ecs-task-execution-dev",
  "taskRoleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/cloudcafe-ecs-task-dev",
  "containerDefinitions": [
    {
      "name": "order-service",
      "image": "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/cloudcafe-order-service:latest",
      "portMappings": [
        {
          "containerPort": 8080,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {"name": "ENVIRONMENT", "value": "dev"},
        {"name": "AWS_REGION", "value": "$AWS_REGION"},
        {"name": "REDIS_HOST", "value": "$REDIS_ENDPOINT"},
        {"name": "REDIS_PORT", "value": "6379"},
        {"name": "DB_HOST", "value": "$RDS_ENDPOINT"},
        {"name": "DB_PORT", "value": "5432"},
        {"name": "DB_NAME", "value": "cloudcafe"},
        {"name": "DB_USER", "value": "cloudcafe_admin"},
        {"name": "DB_PASSWORD", "value": "CloudCafe2024!"},
        {"name": "KINESIS_ORDER_EVENTS_STREAM", "value": "$KINESIS_STREAM"},
        {"name": "DYNAMODB_ACTIVE_ORDERS_TABLE", "value": "$DYNAMODB_TABLE"}
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/cloudcafe-order-service",
          "awslogs-region": "$AWS_REGION",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
EOF

echo ""
echo "=== Registering Task Definition ==="
/usr/local/bin/aws ecs register-task-definition \
    --cli-input-json file:///tmp/order-service-task.json \
    --region $AWS_REGION > /dev/null

echo "✓ Task definition registered"

# Get target group ARN
TARGET_GROUP_ARN=$(/usr/local/bin/aws elbv2 describe-target-groups \
    --names cloudcafe-order-tg-dev \
    --region $AWS_REGION \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text 2>/dev/null || echo "")

echo ""
echo "=== Creating ECS Service ==="

if [ ! -z "$TARGET_GROUP_ARN" ]; then
    echo "Target Group: $TARGET_GROUP_ARN"
    
    # Create service with load balancer
    /usr/local/bin/aws ecs create-service \
        --cluster $ECS_CLUSTER \
        --service-name order-service \
        --task-definition cloudcafe-order-service \
        --desired-count 2 \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[$PRIVATE_SUBNETS],securityGroups=[$TASK_SG],assignPublicIp=DISABLED}" \
        --load-balancers "targetGroupArn=$TARGET_GROUP_ARN,containerName=order-service,containerPort=8080" \
        --health-check-grace-period-seconds 60 \
        --region $AWS_REGION > /dev/null 2>&1 && echo "✓ Service created" || echo "⚠ Service may already exist"
else
    echo "⚠ Target group not found, creating service without LB"
    /usr/local/bin/aws ecs create-service \
        --cluster $ECS_CLUSTER \
        --service-name order-service \
        --task-definition cloudcafe-order-service \
        --desired-count 2 \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[$PRIVATE_SUBNETS],securityGroups=[$TASK_SG],assignPublicIp=DISABLED}" \
        --region $AWS_REGION > /dev/null 2>&1 && echo "✓ Service created" || echo "⚠ Service may already exist"
fi

echo ""
echo "=== Deployment Complete ==="
echo "Service: order-service"
echo "Cluster: $ECS_CLUSTER"
echo "Region: $AWS_REGION"
echo ""
echo "Wait 2-3 minutes for tasks to start and health checks to pass"
echo "Then run: python3 test_endpoints.py"
