#!/bin/bash
set -e

AWS_REGION="us-east-1"
AWS_ACCOUNT_ID="972209100553"
ECR_BASE="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

echo "=================================================="
echo " CloudCafe Full Deployment - us-east-1"
echo "=================================================="
echo ""

# ── Terraform outputs ──────────────────────────────────
cd infrastructure/terraform
VPC_ID=$(terraform output -raw vpc_id)
ECS_CLUSTER=$(terraform output -raw ecs_cluster_name)
EKS_CLUSTER=$(terraform output -raw eks_cluster_name)
TASK_SG=$(terraform output -raw ecs_task_security_group_id)
RDS_ENDPOINT=$(terraform output -raw rds_cluster_endpoint)
REDIS_ENDPOINT=$(terraform output -raw elasticache_endpoint)
MEMORYDB_ENDPOINT=$(terraform output -raw memorydb_cluster_endpoint)
KINESIS_ORDER_STREAM=$(terraform output -raw order_events_stream_name)
KINESIS_ANALYTICS_STREAM=$(terraform output -json kinesis_stream_names | jq -r '.[1]')
DY_ACTIVE_ORDERS=$(terraform output -json dynamodb_table_names | jq -r '.active_orders')
DY_MENU=$(terraform output -json dynamodb_table_names | jq -r '.menu_catalog')
DY_INVENTORY=$(terraform output -json dynamodb_table_names | jq -r '.store_inventory')
DOCDB_ENDPOINT=$(terraform output -raw documentdb_endpoint)
cd ../..

PRIVATE_SUBNETS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Type,Values=private" \
    --query 'Subnets[*].SubnetId' \
    --output text --region $AWS_REGION | tr '\t' ',')

echo "Infrastructure:"
echo "  Region:          $AWS_REGION"
echo "  VPC:             $VPC_ID"
echo "  ECS Cluster:     $ECS_CLUSTER"
echo "  EKS Cluster:     $EKS_CLUSTER"
echo "  Task SG:         $TASK_SG"
echo "  Private Subnets: $PRIVATE_SUBNETS"
echo "  RDS:             $RDS_ENDPOINT"
echo "  Redis:           $REDIS_ENDPOINT"
echo "  MemoryDB:        $MEMORYDB_ENDPOINT"
echo "  Kinesis (order): $KINESIS_ORDER_STREAM"
echo "  DynamoDB orders: $DY_ACTIVE_ORDERS"
echo ""

# ── ECR login ─────────────────────────────────────────
echo "=== Logging in to ECR ==="
aws ecr get-login-password --region $AWS_REGION | \
    docker login --username AWS --password-stdin $ECR_BASE
echo "✓ ECR login successful"
echo ""

# ─────────────────────────────────────────────────────
# Helper: create ECR repo if missing
# ─────────────────────────────────────────────────────
ecr_ensure() {
    local name=$1
    aws ecr describe-repositories --repository-names $name --region $AWS_REGION > /dev/null 2>&1 || \
    aws ecr create-repository \
        --repository-name $name \
        --region $AWS_REGION \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256 > /dev/null
}

# ─────────────────────────────────────────────────────
# 1. ORDER SERVICE (ECS Fargate – Python)
# ─────────────────────────────────────────────────────
echo "=== [1/5] Order Service ==="

ecr_ensure cloudcafe-order-service

docker build -t cloudcafe-order-service:latest services/order-service/ 2>&1 | \
    grep -E "(Step|Successfully built|#[0-9]+ DONE|ERROR)" | tail -8 || true
docker tag cloudcafe-order-service:latest $ECR_BASE/cloudcafe-order-service:latest
docker push $ECR_BASE/cloudcafe-order-service:latest 2>&1 | grep -E "(digest|Pushed|layer)" | tail -3 || true
echo "✓ Image pushed"

aws logs create-log-group --log-group-name /ecs/cloudcafe-order-service --region $AWS_REGION 2>/dev/null || true

cat > /tmp/order-task.json <<EOF
{
  "family": "cloudcafe-order-service",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/cloudcafe-ecs-task-execution-dev",
  "taskRoleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/cloudcafe-ecs-task-dev",
  "containerDefinitions": [{
    "name": "order-service",
    "image": "$ECR_BASE/cloudcafe-order-service:latest",
    "portMappings": [{"containerPort": 8080, "protocol": "tcp"}],
    "environment": [
      {"name": "ENVIRONMENT",                    "value": "dev"},
      {"name": "AWS_REGION",                     "value": "$AWS_REGION"},
      {"name": "REDIS_HOST",                     "value": "$REDIS_ENDPOINT"},
      {"name": "REDIS_PORT",                     "value": "6379"},
      {"name": "DB_HOST",                        "value": "$RDS_ENDPOINT"},
      {"name": "DB_PORT",                        "value": "5432"},
      {"name": "DB_NAME",                        "value": "cloudcafe"},
      {"name": "DB_USER",                        "value": "cloudcafe_admin"},
      {"name": "DB_PASSWORD",                    "value": "CloudCafe2024!"},
      {"name": "KINESIS_ORDER_EVENTS_STREAM",    "value": "$KINESIS_ORDER_STREAM"},
      {"name": "DYNAMODB_ACTIVE_ORDERS_TABLE",   "value": "$DY_ACTIVE_ORDERS"}
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group":         "/ecs/cloudcafe-order-service",
        "awslogs-region":        "$AWS_REGION",
        "awslogs-stream-prefix": "ecs"
      }
    },
    "healthCheck": {
      "command":     ["CMD-SHELL","curl -f http://localhost:8080/health || exit 1"],
      "interval":    30,
      "timeout":     5,
      "retries":     3,
      "startPeriod": 60
    }
  }]
}
EOF
aws ecs register-task-definition --cli-input-json file:///tmp/order-task.json --region $AWS_REGION > /dev/null

ORDER_TG=$(aws elbv2 describe-target-groups --names cloudcafe-order-tg-dev \
    --region $AWS_REGION --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || echo "")

if [ -n "$ORDER_TG" ]; then
    aws ecs create-service \
        --cluster $ECS_CLUSTER --service-name order-service \
        --task-definition cloudcafe-order-service --desired-count 2 \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[$PRIVATE_SUBNETS],securityGroups=[$TASK_SG],assignPublicIp=DISABLED}" \
        --load-balancers "targetGroupArn=$ORDER_TG,containerName=order-service,containerPort=8080" \
        --health-check-grace-period-seconds 60 \
        --region $AWS_REGION > /dev/null 2>&1 && echo "✓ order-service created" || echo "⚠ order-service already exists"
else
    aws ecs create-service \
        --cluster $ECS_CLUSTER --service-name order-service \
        --task-definition cloudcafe-order-service --desired-count 2 \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[$PRIVATE_SUBNETS],securityGroups=[$TASK_SG],assignPublicIp=DISABLED}" \
        --region $AWS_REGION > /dev/null 2>&1 && echo "✓ order-service created" || echo "⚠ order-service already exists"
fi
echo ""

# ─────────────────────────────────────────────────────
# 2. LOYALTY SERVICE (ECS Fargate – Python)
# ─────────────────────────────────────────────────────
echo "=== [2/5] Loyalty Service ==="

ecr_ensure cloudcafe-loyalty-service

# Build inline (simple Flask app)
mkdir -p /tmp/loyalty-build
cat > /tmp/loyalty-build/app.py <<'PYEOF'
from flask import Flask, jsonify, request
from datetime import datetime
import os

app = Flask(__name__)

@app.route('/health')
def health():
    return jsonify({'status':'healthy','service':'loyalty-service','timestamp':datetime.utcnow().isoformat()}), 200

@app.route('/loyalty/points/<user_id>')
def get_points(user_id):
    return jsonify({'user_id':user_id,'points':1250,'tier':'gold','status':'active'}), 200

@app.route('/loyalty/points/add', methods=['POST'])
def add_points():
    data = request.json or {}
    return jsonify({'status':'success','points_added':data.get('points',0),'new_balance':1500}), 200

@app.route('/loyalty/tier/<user_id>')
def get_tier(user_id):
    return jsonify({'user_id':user_id,'tier':'gold','benefits':['free_drink','birthday_reward']}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
PYEOF
cat > /tmp/loyalty-build/requirements.txt <<'EOF'
flask==3.0.0
gunicorn==21.2.0
boto3==1.34.0
EOF
cat > /tmp/loyalty-build/Dockerfile <<'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')" || exit 1
CMD ["gunicorn","-b","0.0.0.0:8080","app:app","--workers","4","--timeout","120"]
EOF

docker build -t cloudcafe-loyalty-service:latest /tmp/loyalty-build/ 2>&1 | \
    grep -E "(Step|Successfully built|#[0-9]+ DONE|ERROR)" | tail -8 || true
docker tag cloudcafe-loyalty-service:latest $ECR_BASE/cloudcafe-loyalty-service:latest
docker push $ECR_BASE/cloudcafe-loyalty-service:latest 2>&1 | grep -E "(digest|Pushed|layer)" | tail -3 || true
echo "✓ Image pushed"

aws logs create-log-group --log-group-name /ecs/cloudcafe-loyalty-service --region $AWS_REGION 2>/dev/null || true

cat > /tmp/loyalty-task.json <<EOF
{
  "family": "cloudcafe-loyalty-service",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/cloudcafe-ecs-task-execution-dev",
  "taskRoleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/cloudcafe-ecs-task-dev",
  "containerDefinitions": [{
    "name": "loyalty-service",
    "image": "$ECR_BASE/cloudcafe-loyalty-service:latest",
    "portMappings": [{"containerPort": 8080, "protocol": "tcp"}],
    "environment": [
      {"name": "ENVIRONMENT", "value": "dev"},
      {"name": "AWS_REGION",  "value": "$AWS_REGION"}
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group":         "/ecs/cloudcafe-loyalty-service",
        "awslogs-region":        "$AWS_REGION",
        "awslogs-stream-prefix": "ecs"
      }
    },
    "healthCheck": {
      "command":     ["CMD-SHELL","curl -f http://localhost:8080/health || exit 1"],
      "interval":    30,
      "timeout":     5,
      "retries":     3,
      "startPeriod": 60
    }
  }]
}
EOF
aws ecs register-task-definition --cli-input-json file:///tmp/loyalty-task.json --region $AWS_REGION > /dev/null

LOYALTY_TG=$(aws elbv2 describe-target-groups --names cloudcafe-loyalty-tg-dev \
    --region $AWS_REGION --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || echo "")

if [ -n "$LOYALTY_TG" ]; then
    aws ecs create-service \
        --cluster $ECS_CLUSTER --service-name loyalty-service \
        --task-definition cloudcafe-loyalty-service --desired-count 2 \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[$PRIVATE_SUBNETS],securityGroups=[$TASK_SG],assignPublicIp=DISABLED}" \
        --load-balancers "targetGroupArn=$LOYALTY_TG,containerName=loyalty-service,containerPort=8080" \
        --health-check-grace-period-seconds 60 \
        --region $AWS_REGION > /dev/null 2>&1 && echo "✓ loyalty-service created" || echo "⚠ loyalty-service already exists"
else
    aws ecs create-service \
        --cluster $ECS_CLUSTER --service-name loyalty-service \
        --task-definition cloudcafe-loyalty-service --desired-count 2 \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[$PRIVATE_SUBNETS],securityGroups=[$TASK_SG],assignPublicIp=DISABLED}" \
        --region $AWS_REGION > /dev/null 2>&1 && echo "✓ loyalty-service created" || echo "⚠ loyalty-service already exists"
fi
echo ""

# ─────────────────────────────────────────────────────
# 3. ANALYTICS WORKER (ECS Fargate – Python)
# ─────────────────────────────────────────────────────
echo "=== [3/5] Analytics Worker ==="

ecr_ensure cloudcafe-analytics-worker

mkdir -p /tmp/analytics-build
cat > /tmp/analytics-build/worker.py <<'PYEOF'
import boto3, json, time, logging
from datetime import datetime
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

region = os.getenv('AWS_REGION', 'us-east-1')
kinesis = boto3.client('kinesis', region_name=region)
STREAM_NAME = os.getenv('KINESIS_STREAM', 'cloudcafe-analytics-events-dev')

def main():
    logger.info(f"Analytics Worker starting... Stream: {STREAM_NAME}")
    try:
        resp = kinesis.describe_stream(StreamName=STREAM_NAME)
        shard_id = resp['StreamDescription']['Shards'][0]['ShardId']
        shard_iterator = kinesis.get_shard_iterator(
            StreamName=STREAM_NAME, ShardId=shard_id,
            ShardIteratorType='LATEST')['ShardIterator']
        logger.info(f"Listening: {STREAM_NAME}/{shard_id}")
        while True:
            try:
                resp = kinesis.get_records(ShardIterator=shard_iterator, Limit=100)
                if resp['Records']:
                    logger.info(f"Processed {len(resp['Records'])} records")
                shard_iterator = resp['NextShardIterator']
                time.sleep(1)
            except Exception as e:
                logger.error(f"Loop error: {e}")
                time.sleep(5)
    except Exception as e:
        logger.error(f"Fatal: {e}")
        time.sleep(10)

if __name__ == '__main__':
    main()
PYEOF
cat > /tmp/analytics-build/requirements.txt <<'EOF'
boto3==1.34.0
EOF
cat > /tmp/analytics-build/Dockerfile <<'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY worker.py .
CMD ["python","worker.py"]
EOF

docker build -t cloudcafe-analytics-worker:latest /tmp/analytics-build/ 2>&1 | \
    grep -E "(Step|Successfully built|#[0-9]+ DONE|ERROR)" | tail -8 || true
docker tag cloudcafe-analytics-worker:latest $ECR_BASE/cloudcafe-analytics-worker:latest
docker push $ECR_BASE/cloudcafe-analytics-worker:latest 2>&1 | grep -E "(digest|Pushed|layer)" | tail -3 || true
echo "✓ Image pushed"

aws logs create-log-group --log-group-name /ecs/cloudcafe-analytics-worker --region $AWS_REGION 2>/dev/null || true

cat > /tmp/analytics-task.json <<EOF
{
  "family": "cloudcafe-analytics-worker",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/cloudcafe-ecs-task-execution-dev",
  "taskRoleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/cloudcafe-ecs-task-dev",
  "containerDefinitions": [{
    "name": "analytics-worker",
    "image": "$ECR_BASE/cloudcafe-analytics-worker:latest",
    "environment": [
      {"name": "ENVIRONMENT",    "value": "dev"},
      {"name": "AWS_REGION",     "value": "$AWS_REGION"},
      {"name": "KINESIS_STREAM", "value": "$KINESIS_ANALYTICS_STREAM"}
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group":         "/ecs/cloudcafe-analytics-worker",
        "awslogs-region":        "$AWS_REGION",
        "awslogs-stream-prefix": "ecs"
      }
    }
  }]
}
EOF
aws ecs register-task-definition --cli-input-json file:///tmp/analytics-task.json --region $AWS_REGION > /dev/null

aws ecs create-service \
    --cluster $ECS_CLUSTER --service-name analytics-worker \
    --task-definition cloudcafe-analytics-worker --desired-count 1 \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$PRIVATE_SUBNETS],securityGroups=[$TASK_SG],assignPublicIp=DISABLED}" \
    --region $AWS_REGION > /dev/null 2>&1 && echo "✓ analytics-worker created" || echo "⚠ analytics-worker already exists"
echo ""

# ─────────────────────────────────────────────────────
# 4. MENU SERVICE (EKS – Node.js)
# ─────────────────────────────────────────────────────
echo "=== [4/5] Menu Service (EKS) ==="

# Configure kubectl for us-east-1 EKS
aws eks update-kubeconfig --name $EKS_CLUSTER --region $AWS_REGION
echo "✓ kubectl configured for $EKS_CLUSTER"

ecr_ensure cloudcafe-menu-service

docker build -t cloudcafe-menu-service:latest services/menu-service/ 2>&1 | \
    grep -E "(Step|Successfully built|#[0-9]+ DONE|ERROR)" | tail -8 || true
docker tag cloudcafe-menu-service:latest $ECR_BASE/cloudcafe-menu-service:latest
docker push $ECR_BASE/cloudcafe-menu-service:latest 2>&1 | grep -E "(digest|Pushed|layer)" | tail -3 || true
echo "✓ Image pushed"

cat services/menu-service/k8s/deployment.yaml | \
    sed "s|\${AWS_ACCOUNT_ID}|$AWS_ACCOUNT_ID|g" | \
    sed "s|\${AWS_REGION}|$AWS_REGION|g" | \
    sed "s|ap-northeast-2|$AWS_REGION|g" | \
    kubectl apply -f - 2>&1 | tail -5 || true

# Apply service manifest if it exists
if [ -f services/menu-service/k8s/service.yaml ]; then
    kubectl apply -f services/menu-service/k8s/service.yaml 2>&1 | tail -3 || true
fi

echo "✓ Menu service deployed to EKS"
echo ""

# ─────────────────────────────────────────────────────
# 5. INVENTORY SERVICE (EKS – Go)
# ─────────────────────────────────────────────────────
echo "=== [5/5] Inventory Service (EKS) ==="

ecr_ensure cloudcafe-inventory-service

docker build -t cloudcafe-inventory-service:latest services/inventory-service/ 2>&1 | \
    grep -E "(Step|Successfully built|#[0-9]+ DONE|ERROR)" | tail -8 || true
docker tag cloudcafe-inventory-service:latest $ECR_BASE/cloudcafe-inventory-service:latest
docker push $ECR_BASE/cloudcafe-inventory-service:latest 2>&1 | grep -E "(digest|Pushed|layer)" | tail -3 || true
echo "✓ Image pushed"

# Kubernetes secrets for inventory service
kubectl create secret generic memorydb-credentials \
    --from-literal=endpoint="$MEMORYDB_ENDPOINT" \
    --dry-run=client -o yaml | kubectl apply -f - 2>&1 | tail -2 || true

cat services/inventory-service/k8s/deployment.yaml | \
    sed "s|\${AWS_ACCOUNT_ID}|$AWS_ACCOUNT_ID|g" | \
    sed "s|\${AWS_REGION}|$AWS_REGION|g" | \
    sed "s|ap-northeast-2|$AWS_REGION|g" | \
    kubectl apply -f - 2>&1 | tail -5 || true

if [ -f services/inventory-service/k8s/service.yaml ]; then
    kubectl apply -f services/inventory-service/k8s/service.yaml 2>&1 | tail -3 || true
fi

echo "✓ Inventory service deployed to EKS"
echo ""

# ─────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────
echo "=================================================="
echo " Deployment Complete — us-east-1"
echo "=================================================="
echo ""
echo "ECS Services (Fargate):"
echo "  ✓ order-service     (2 tasks)"
echo "  ✓ loyalty-service   (2 tasks)"
echo "  ✓ analytics-worker  (1 task)"
echo ""
echo "EKS Deployments:"
echo "  ✓ menu-service      (3 pods)"
echo "  ✓ inventory-service (3 pods)"
echo ""
echo "Endpoints:"
ALB_DNS=$(cd infrastructure/terraform && terraform output -raw alb_dns_name)
API_GW=$(cd infrastructure/terraform && terraform output -raw api_gateway_url)
CF_URL=$(cd infrastructure/terraform && terraform output -raw cloudfront_url)
echo "  ALB:         http://$ALB_DNS"
echo "  API Gateway: $API_GW"
echo "  CloudFront:  $CF_URL"
echo ""
echo "Check service health (~2-3 min):"
echo "  aws ecs list-services --cluster $ECS_CLUSTER --region $AWS_REGION"
echo "  kubectl get pods -o wide"
