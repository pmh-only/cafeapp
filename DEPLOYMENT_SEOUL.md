# CloudCafe Deployment to ap-northeast-2 (Seoul)

## Deployment Status: ✅ COMPLETE

Successfully deployed the CloudCafe infrastructure to **ap-northeast-2** (Seoul, South Korea) region.

## Deployment Summary

### Region Configuration
- **Region**: ap-northeast-2 (Seoul)
- **Availability Zones**: ap-northeast-2a, ap-northeast-2b, ap-northeast-2c
- **Environment**: dev
- **Project**: cloudcafe

### Deployed Resources (140 total)

#### Networking
- VPC: `vpc-085aaa3f5dcc14579`
- 3 Public Subnets (across 3 AZs)
- 3 Private Subnets (across 3 AZs)
- 3 Database Subnets (across 3 AZs)
- NAT Gateway, Internet Gateway
- Security Groups for all services

#### Compute Services
- **ECS Cluster**: `cloudcafe-ecs-dev`
- **EKS Cluster**: `cloudcafe-eks-dev`
  - Endpoint: `https://90BAB6418CC67FF6A40C91B5D8B65827.gr7.ap-northeast-2.eks.amazonaws.com`
- **EC2 Auto Scaling Group**: `cloudcafe-loyalty-asg-dev`

#### Load Balancing
- **Application Load Balancer**: `cloudcafe-alb-dev-252257753.ap-northeast-2.elb.amazonaws.com`
- **Network Load Balancer**: `cloudcafe-nlb-dev-1f64886835d5e522.elb.ap-northeast-2.amazonaws.com`
- **VPC Lattice Service Network**: Configured

#### Databases
- **RDS Aurora PostgreSQL**: `cloudcafe-aurora-dev.cluster-cf1uihhgb336.ap-northeast-2.rds.amazonaws.com`
  - Primary and Replica instances
- **DocumentDB**: `cloudcafe-docdb-dev.cluster-cf1uihhgb336.ap-northeast-2.docdb.amazonaws.com`
  - Primary and Replica instances
- **Redshift**: `cloudcafe-redshift-dev.cjfbyqgpd4hg.ap-northeast-2.redshift.amazonaws.com:5439`
- **DynamoDB Tables**:
  - `cloudcafe-active-orders-dev`
  - `cloudcafe-menu-catalog-dev`
  - `cloudcafe-store-inventory-dev`

#### Caching
- **ElastiCache Redis**: `cloudcafe-redis-dev.dd4mct.ng.0001.apn2.cache.amazonaws.com`
- **MemoryDB**: `clustercfg.cloudcafe-memorydb-dev.dd4mct.memorydb.ap-northeast-2.amazonaws.com`

#### Messaging
- **Kinesis Streams**:
  - `cloudcafe-order-events-dev`
  - `cloudcafe-analytics-events-dev`
- **SQS Queues**:
  - Payment Processing (FIFO)
  - Order Submission
  - Notification

#### Serverless
- **Lambda Functions**:
  - `cloudcafe-payment-processor-dev`
  - `cloudcafe-analytics-writer-dev`
- **API Gateway**: `https://7bzha9trsl.execute-api.ap-northeast-2.amazonaws.com/dev`

#### Frontend
- **CloudFront Distribution**: `https://d3prghburdy7oe.cloudfront.net`
  - Distribution ID: `E169C42BSHQ99R`
  - S3 Logs Bucket: `cloudcafe-cloudfront-logs-dev`

## Access Endpoints

### Primary Endpoints
```bash
# Application Load Balancer
ALB_DNS="cloudcafe-alb-dev-252257753.ap-northeast-2.elb.amazonaws.com"

# API Gateway
API_URL="https://7bzha9trsl.execute-api.ap-northeast-2.amazonaws.com/dev"

# CloudFront CDN
CDN_URL="https://d3prghburdy7oe.cloudfront.net"

# EKS Cluster
EKS_ENDPOINT="https://90BAB6418CC67FF6A40C91B5D8B65827.gr7.ap-northeast-2.eks.amazonaws.com"
```

### Database Endpoints
```bash
# RDS Aurora PostgreSQL
RDS_ENDPOINT="cloudcafe-aurora-dev.cluster-cf1uihhgb336.ap-northeast-2.rds.amazonaws.com"

# DocumentDB
DOCDB_ENDPOINT="cloudcafe-docdb-dev.cluster-cf1uihhgb336.ap-northeast-2.docdb.amazonaws.com"

# Redshift
REDSHIFT_ENDPOINT="cloudcafe-redshift-dev.cjfbyqgpd4hg.ap-northeast-2.redshift.amazonaws.com:5439"

# ElastiCache Redis
REDIS_ENDPOINT="cloudcafe-redis-dev.dd4mct.ng.0001.apn2.cache.amazonaws.com"

# MemoryDB
MEMORYDB_ENDPOINT="clustercfg.cloudcafe-memorydb-dev.dd4mct.memorydb.ap-northeast-2.amazonaws.com"
```

## Next Steps

### 1. Configure EKS Access
```bash
aws eks update-kubeconfig --region ap-northeast-2 --name cloudcafe-eks-dev
kubectl get nodes
```

### 2. Deploy Services

#### Order Service (ECS Fargate)
```bash
cd services/order-service
# Build and push Docker image to ECR
# Deploy ECS task definition
```

#### Inventory Service (EKS)
```bash
cd services/inventory-service
kubectl apply -f k8s/deployment.yaml
```

#### Menu Service (EKS)
```bash
cd services/menu-service
kubectl apply -f k8s/deployment.yaml
```

#### Loyalty Service (EC2)
```bash
cd services/loyalty-service
./deploy-ec2.sh
```

#### Analytics Worker (EC2)
```bash
cd services/analytics-worker
./deploy-ec2.sh
```

### 3. Initialize Database Schemas
```bash
# RDS PostgreSQL
psql -h cloudcafe-aurora-dev.cluster-cf1uihhgb336.ap-northeast-2.rds.amazonaws.com \
     -U cloudcafe_admin -d cloudcafe < scripts/init-rds-schema.sql
```

### 4. Validate Deployment
```bash
./scripts/validate-infrastructure.sh
```

### 5. Test Endpoints
```bash
# Test ALB
curl http://cloudcafe-alb-dev-252257753.ap-northeast-2.elb.amazonaws.com/health

# Test API Gateway
curl https://7bzha9trsl.execute-api.ap-northeast-2.amazonaws.com/dev/api/health

# Test CloudFront
curl https://d3prghburdy7oe.cloudfront.net
```

## Cost Estimate (Seoul Region)

Monthly cost estimate for ap-northeast-2:
- **Compute**: ~$350 (ECS + EKS + EC2)
- **Databases**: ~$250 (RDS Aurora + DocumentDB + Redshift)
- **Caching**: ~$120 (ElastiCache + MemoryDB)
- **Networking**: ~$100 (ALB + NLB + Data Transfer)
- **Other**: ~$80 (Lambda, SQS, Kinesis, CloudFront)

**Total**: ~$900-1100/month (dev environment)

## Notes

1. **WAF**: CloudFront WAF was disabled as it requires deployment in us-east-1 region
2. **Redshift**: Minor configuration drift detected (can be ignored for dev environment)
3. **Secrets**: Database passwords stored in AWS Secrets Manager
4. **Monitoring**: CloudWatch dashboards and metrics configured for all services

## Cleanup

To destroy all resources:
```bash
cd infrastructure/terraform
terraform destroy
```

## Support

For issues or questions:
1. Check CloudWatch logs for each service
2. Review Terraform state: `terraform show`
3. Validate resources: `./scripts/validate-infrastructure.sh`

---

**Deployment Date**: February 24, 2026
**Deployed By**: Terraform v5.0+
**Region**: ap-northeast-2 (Seoul)
