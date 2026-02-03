# CloudCafe Quick Start Guide

Get CloudCafe running in under 30 minutes.

## Prerequisites Checklist

- [ ] AWS Account with admin access
- [ ] AWS CLI installed and configured (`aws configure`)
- [ ] Terraform >= 1.5.0 installed
- [ ] Docker installed (for building images)
- [ ] kubectl installed (for EKS)
- [ ] Minimum $100/month AWS budget

## Step-by-Step Deployment

### 1. Clone and Setup (2 minutes)

```bash
cd cafeapp
ls -la  # Verify project structure
```

### 2. Configure AWS Region (1 minute)

Edit `infrastructure/terraform/variables.tf`:

```hcl
variable "aws_region" {
  default = "us-east-1"  # Change to your preferred region
}
```

### 3. Deploy Infrastructure (15-20 minutes)

```bash
cd infrastructure/terraform

# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Deploy (confirm with 'yes')
terraform apply
```

**What gets deployed:**
- VPC with 3 AZs, public/private subnets
- RDS Aurora PostgreSQL cluster (2 instances)
- DynamoDB tables (3 tables)
- DocumentDB cluster
- Redshift cluster
- ElastiCache Redis
- MemoryDB cluster
- ECS cluster
- EKS cluster
- EC2 Auto Scaling Group
- SQS queues
- Kinesis streams
- Security groups, IAM roles, etc.

### 4. Initialize Database Schema (3 minutes)

```bash
# Get RDS endpoint
RDS_ENDPOINT=$(terraform output -raw rds_cluster_endpoint)
echo $RDS_ENDPOINT

# Get password from Secrets Manager
SECRET_ARN=$(terraform output -raw rds_secret_arn)
DB_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id $SECRET_ARN \
  --query SecretString \
  --output text | jq -r .password)

# Connect to RDS (requires psql client)
psql -h $RDS_ENDPOINT -U cloudcafe_admin -d cloudcafe

# Run initialization SQL
\i ../../scripts/init-rds-schema.sql

# Exit psql
\q
```

### 5. Build and Deploy Order Service (5 minutes)

```bash
cd ../../services/order-service

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=us-east-1

# Create ECR repository
aws ecr create-repository \
  --repository-name cloudcafe-order-service \
  --region $AWS_REGION

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Build and push
docker build -t cloudcafe-order-service .
docker tag cloudcafe-order-service:latest \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/cloudcafe-order-service:latest
docker push \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/cloudcafe-order-service:latest
```

### 6. Validate Deployment (2 minutes)

```bash
cd ../../scripts
./validate-infrastructure.sh
```

Expected output:
```
━━━ Network Infrastructure ━━━
  Checking VPC... ✓
  Checking Subnets... ✓
  Checking Security Groups... ✓

━━━ Compute Services ━━━
  Checking ECS Cluster... ✓
  Checking EKS Cluster... ✓
  Checking EC2 Auto Scaling Groups... ✓

...

✅ All validation checks passed!
```

### 7. Test Order Service (1 minute)

```bash
# Get ALB DNS name
cd ../infrastructure/terraform
ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null || echo "not-deployed-yet")

# Test health endpoint
curl http://$ALB_DNS/health

# Create test order
curl -X POST http://$ALB_DNS/orders \
  -H "Content-Type: application/json" \
  -d '{
    "customer_id": "test-user-1",
    "store_id": "1",
    "items": [
      {"item_id": "latte", "quantity": 2, "price": 5.0}
    ]
  }'
```

### 8. Open CloudWatch Dashboard (1 minute)

```bash
# Get CloudWatch dashboard URL
REGION=us-east-1
echo "https://console.aws.amazon.com/cloudwatch/home?region=$REGION#dashboards:"
```

Import the dashboard:
1. Go to CloudWatch → Dashboards
2. Create Dashboard
3. Actions → View/Edit Source
4. Paste contents of `dashboard_full.json`
5. Save

## Quick Tests

### Run Stress Scenario

```bash
# Trigger Morning Rush stress (5 minutes of 95% CPU)
curl -X POST http://$ALB_DNS/stress/morning-rush \
  -H "Content-Type: application/json" \
  -d '{"duration_seconds": 300, "target_cpu": 95}'

# Watch CloudWatch dashboard for CPU spike
```

### Run Chaos Experiment

```bash
cd ../chaos/scenarios

# Kill 50% of ECS tasks
./06-ecs-task-kill.sh

# Watch CloudWatch dashboard for task count drop and recovery
```

## Common Issues & Solutions

### Issue: Terraform apply fails with "InvalidParameterException"

**Cause:** AWS API rate limiting or transient error

**Solution:**
```bash
# Wait 30 seconds and retry
sleep 30
terraform apply
```

### Issue: Docker build fails with "no space left on device"

**Solution:**
```bash
# Clean Docker images
docker system prune -a
```

### Issue: Cannot connect to RDS

**Cause:** Security group rules or running from outside VPC

**Solution:**
```bash
# Use EC2 bastion host or AWS Systems Manager Session Manager
aws ssm start-session --target <instance-id>
```

### Issue: ECS tasks won't start

**Cause:** Missing ECR image or incorrect task definition

**Solution:**
```bash
# Check ECR repository exists
aws ecr describe-repositories --repository-names cloudcafe-order-service

# Check task definition
aws ecs describe-task-definition --task-definition cloudcafe-order-service
```

## Next Steps

Once deployed:

1. **Review Metrics** - Check CloudWatch dashboard for all service metrics
2. **Load Testing** - Run K6 load tests: `k6 run load-testing/k6/scenarios/morning-rush.js`
3. **Chaos Engineering** - Execute chaos scenarios: `./chaos/master-chaos.sh`
4. **Deploy More Services** - Build and deploy inventory, menu, loyalty services
5. **Custom Scenarios** - Create your own stress and chaos scenarios

## Cleanup

To avoid ongoing charges:

```bash
# Destroy all infrastructure
cd infrastructure/terraform
terraform destroy

# Confirm with 'yes'
```

**Note:** This will permanently delete:
- All databases and their data
- All running services
- All CloudWatch logs
- Everything except ECR images (delete manually if needed)

## Cost Management

### Daily Cost (~$30-40/day)

To minimize costs during development:

```bash
# Stop Redshift cluster (saves ~$6/day)
aws redshift pause-cluster --cluster-identifier cloudcafe-redshift-dev

# Resume when needed
aws redshift resume-cluster --cluster-identifier cloudcafe-redshift-dev

# Reduce EKS node group to 1 node
aws eks update-nodegroup-config \
  --cluster-name cloudcafe-eks-dev \
  --nodegroup-name cloudcafe-eks-node-group-dev \
  --scaling-config minSize=1,maxSize=1,desiredSize=1
```

## Getting Help

1. Check `README.md` for detailed documentation
2. Review CloudWatch logs: `/ecs/cloudcafe-order-service`
3. Check service health endpoints
4. Review Terraform outputs: `terraform output`
5. Validate infrastructure: `./scripts/validate-infrastructure.sh`

## Success Criteria

You've successfully deployed CloudCafe when:

- ✅ `terraform apply` completes without errors
- ✅ Validation script shows all checks passing
- ✅ Order service health endpoint returns 200 OK
- ✅ CloudWatch dashboard shows metrics for all services
- ✅ Stress scenario triggers CPU spike visible in dashboard
- ✅ Chaos experiment shows expected impact and recovery

Congratulations! 🎉 You now have a production-grade AWS infrastructure with chaos engineering capabilities.
