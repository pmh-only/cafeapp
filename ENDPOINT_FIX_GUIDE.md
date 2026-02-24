# CloudCafe Endpoint Fix Guide

## Current Status
- Infrastructure: ✅ Deployed
- Services: ❌ Not deployed (causing 503 errors)
- Databases: ✅ Operational

## Quick Fix Options

### Option 1: Deploy Health Check Service (Fastest)

1. Build the health check service:
```bash
cd /tmp/health-service
docker build -t cloudcafe-health:latest .
```

2. Push to ECR and deploy to ECS (requires AWS CLI configured)

### Option 2: Deploy Real Services

Deploy the actual services from the services/ directory:

1. **Order Service** (ECS Fargate):
```bash
cd services/order-service
docker build -t order-service .
# Push to ECR and deploy
```

2. **Menu Service** (EKS):
```bash
cd services/menu-service
docker build -t menu-service .
kubectl apply -f k8s/deployment.yaml
```

3. **Inventory Service** (EKS):
```bash
cd services/inventory-service
docker build -t inventory-service .
kubectl apply -f k8s/deployment.yaml
```

4. **Loyalty Service** (EC2):
```bash
cd services/loyalty-service
./deploy-ec2.sh
```

## Why Endpoints Are Failing

1. **503 Service Unavailable**: ALB target groups have no healthy targets
2. **API Gateway Timeouts**: VPC Link trying to reach NLB with no backends
3. **Database Timeouts**: Correct behavior (security groups blocking external access)

## Expected Results After Fix

- ALB endpoints: 200 OK
- API Gateway: 200 OK
- CloudFront: 200 OK (via ALB origin)
- All service endpoints: 200 OK

## Infrastructure Details

- ECS Cluster: cloudcafe-ecs-dev
- VPC ID: vpc-085aaa3f5dcc14579
- ALB DNS: cloudcafe-alb-dev-252257753.ap-northeast-2.elb.amazonaws.com
- Region: ap-northeast-2

## Testing After Deployment

```bash
python3 test_endpoints.py
```

Expected: 100% pass rate (24/24 tests)
