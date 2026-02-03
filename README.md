# CloudCafe: Large-Scale Coffee Order Service

A comprehensive, production-grade AWS infrastructure demonstration featuring **17 AWS services**, chaos engineering, and complete observability through CloudWatch dashboards.

## 🎯 Overview

CloudCafe is a multi-service coffee ordering platform designed to simulate a Starbucks-scale operation (30K stores, 100M users, 5M daily orders). It demonstrates:

- **Complete AWS service integration** (17 services)
- **Built-in CPU stress scenarios** with storytelling
- **12+ chaos engineering scripts** for resilience testing
- **Polyglot microservices** (Python, Go, Node.js, Java)
- **Rich CloudWatch metrics** and dashboards
- **Production-ready patterns** (auto-scaling, failover, caching)

## 🏗️ Architecture

### AWS Services Used (17 Total)

**Compute:**
- EC2 (Auto Scaling Groups)
- ECS with Fargate
- EKS (Kubernetes)
- Lambda
- Auto Scaling

**Networking:**
- Application Load Balancer (ALB)
- Network Load Balancer (NLB)
- VPC Lattice
- CloudFront
- API Gateway

**Databases:**
- RDS Aurora PostgreSQL
- DynamoDB
- DocumentDB
- ElastiCache (Redis)
- MemoryDB
- Redshift

**Messaging:**
- SQS
- Kinesis Data Streams

### Microservices

1. **Order Service** (Python Flask on ECS Fargate)
   - Order CRUD operations
   - RDS + DynamoDB integration
   - Morning Rush stress scenario

2. **Inventory Service** (Go on EKS)
   - Store inventory management
   - DynamoDB + MemoryDB integration
   - Restock Storm stress scenario

3. **Loyalty Service** (Java Spring Boot on EC2)
   - Customer loyalty points
   - RDS integration
   - Batch calculation stress scenario

4. **Menu Service** (Node.js Express on EKS)
   - Menu catalog management
   - DocumentDB + ElastiCache integration
   - Menu Sync stress scenario

5. **Payment Processor** (Python Lambda)
   - Payment processing
   - SQS triggered
   - Cold start stress scenario

6. **Analytics Worker** (Python on EC2)
   - Kinesis consumer
   - Redshift analytics
   - Query storm stress scenario

## 🚀 Quick Start

### Prerequisites

- AWS Account with appropriate permissions
- Terraform >= 1.5.0
- AWS CLI configured (`aws configure`)
- Docker (for building service images)
- kubectl (for EKS management)
- redis-cli (for chaos testing)

### One-Command Deployment

```bash
# Deploy entire infrastructure
./scripts/deploy-all.sh
```

### Manual Deployment

```bash
# 1. Deploy infrastructure
cd infrastructure/terraform
terraform init
terraform plan
terraform apply

# 2. Build and push service images
cd ../../services/order-service
docker build -t order-service .
# Push to ECR...

# 3. Deploy services
# (See individual service README files)

# 4. Validate deployment
cd ../../scripts
./validate-infrastructure.sh
```

## 📊 CloudWatch Dashboard

The infrastructure emits metrics to CloudWatch for comprehensive observability:

### Key Metrics by Service

| Service | Key Metrics | Dashboard Widget |
|---------|-------------|------------------|
| ECS | `TaskCpuUtilization`, `RunningTaskCount` | ECS Task CPU Utilization |
| EKS | `pod_cpu_utilization`, `pod_restart_count` | EKS Pod CPU |
| Lambda | `Errors`, `Duration`, `ConcurrentExecutions` | Lambda Errors |
| ALB | `RequestCount`, `HTTPCode_Target_5XX_Count` | ALB 5XX Errors |
| RDS | `DatabaseConnections`, `CPUUtilization` | RDS Connections |
| DynamoDB | `UserErrors`, `ConsumedReadCapacityUnits` | DynamoDB Throttles |
| ElastiCache | `CacheHits`, `CacheMisses`, `CPUUtilization` | Cache Hit Rate |
| Kinesis | `IncomingRecords`, `GetRecords.IteratorAgeMilliseconds` | Kinesis Throughput |

### Custom Application Metrics

Services emit custom metrics to `CloudCafe/*` namespace:

```python
# Example from Order Service
cloudwatch.put_metric_data(
    Namespace='CloudCafe/OrderService',
    MetricData=[{
        'MetricName': 'CPUStressLevel',
        'Value': psutil.cpu_percent(),
        'Dimensions': [{'Name': 'Scenario', 'Value': 'MorningRush'}]
    }]
)
```

## 🔥 Stress Scenarios

Built-in CPU stress scenarios to test infrastructure observability:

### 1. Morning Rush (Order Service - ECS)
```bash
curl -X POST http://<alb-endpoint>/stress/morning-rush \
  -H "Content-Type: application/json" \
  -d '{"duration_seconds": 300, "target_cpu": 95}'
```

**Story:** 7:45 AM Monday. Corporate bulk orders spike.

**Impact:**
- ECS task CPU → 95%
- Response time → 500ms+ (from 50ms)
- Task count increases (auto-scaling)
- CloudWatch dashboard shows CPU spike

### 2. Inventory Restock Storm (Inventory Service - EKS)

**Story:** Weekly restock. All stores update 5000+ SKUs simultaneously.

**Impact:**
- EKS pod CPU → 80%
- Pod restart count may increase
- DynamoDB write capacity consumed

### 3. Loyalty Batch Calculation (Loyalty Service - EC2)

**Story:** Hourly recalculation for 10M customers.

**Impact:**
- EC2 CPU → 100%
- Auto Scaling Group scales out
- Response time degradation

### 4. Menu Sync Storm (Menu Service - EKS)

**Story:** Marketing pushes seasonal menu. All pods sync 10K items.

**Impact:**
- DocumentDB CPU spike
- ElastiCache evictions
- Network throughput increase

### 5. Cold Start Avalanche (Payment Processor - Lambda)

**Story:** Black Friday. 10K concurrent Lambda cold starts.

**Impact:**
- Lambda duration → 3s+ (cold start)
- SQS message age increases
- CloudWatch shows Lambda errors

### 6. Query Storm (Analytics Worker - EC2)

**Story:** End of quarter reports. 500 concurrent Redshift queries.

**Impact:**
- Redshift CPU → 90%
- Query duration increases
- Kinesis iterator age increases

## ⚡ Chaos Engineering

### Available Chaos Scenarios

Execute from `chaos/scenarios/`:

**Network Failures:**
- `01-alb-routing-failure.sh` - Delete ALB routing rules
- `10-security-group-lockdown.sh` - Revoke security group ingress

**Compute Failures:**
- `06-ecs-task-kill.sh` - Terminate 50% of ECS tasks
- `07-eks-node-drain.sh` - Drain Kubernetes node

**Database Failures:**
- `03-rds-failover.sh` - Trigger Aurora failover
- `04-dynamodb-throttle.sh` - Reduce DynamoDB capacity

**Cache Failures:**
- `05-elasticache-flush.sh` - Flush Redis cache
- `08-memorydb-restart.sh` - Restart MemoryDB cluster

### Running Chaos Experiments

**Single scenario:**
```bash
cd chaos/scenarios
./06-ecs-task-kill.sh
```

**Master orchestration (all scenarios):**
```bash
cd chaos
./master-chaos.sh
```

### Chaos Script Features

- ✅ Confirmation prompts before injection
- ✅ Backup/restore procedures
- ✅ Expected impact documentation
- ✅ Real-time monitoring
- ✅ Recovery validation
- ✅ CloudWatch dashboard integration

### Example Output

```
🔥 CHAOS ENGINEERING EXPERIMENT
Scenario: ECS Task Kill (50% capacity loss)
Expected Impact: Task count drops 50%, CPU spikes on remaining tasks

Continue? (yes/no): yes

[INFO] Found 4 running tasks
[INFO] Will kill 2 tasks (50%)
🔥 Stopping task: abc123...
✅ Chaos injected: Killed 2 tasks

Expected CloudWatch Dashboard Indicators:
  • ECS Running Task Count → Drops from 4 to 2
  • ECS Task CPU Utilization → Spikes (2x load per task)
  • ALB 5XX Errors → Brief spike during transition

[120s] Recovery check...
✅ Full recovery complete! All tasks restored.
```

## 📈 Load Testing

K6 load test scenarios in `load-testing/k6/scenarios/`:

### Morning Rush Load Test

```bash
cd load-testing
k6 run k6/scenarios/morning-rush.js
```

**Profile:**
- Ramp up: 2 min to 100 VUs
- Sustained: 5 min at 1000 VUs
- Ramp down: 2 min to 0

**Endpoints tested:**
- `POST /api/orders` (order creation)
- `GET /api/menu/items` (menu retrieval)
- `GET /api/loyalty/points/:userId` (loyalty lookup)

## 🗂️ Project Structure

```
cafeapp/
├── infrastructure/terraform/      # Infrastructure as Code
│   ├── main.tf                   # Root module
│   ├── variables.tf              # Global variables
│   ├── outputs.tf                # Resource ARNs for chaos scripts
│   └── modules/
│       ├── networking/           # VPC, subnets, security groups
│       ├── databases/            # RDS, DynamoDB, DocumentDB, Redshift
│       ├── caching/              # ElastiCache, MemoryDB
│       ├── compute/              # EC2, ECS, EKS
│       ├── loadbalancing/        # ALB, NLB, VPC Lattice
│       ├── messaging/            # SQS, Kinesis
│       ├── serverless/           # Lambda, API Gateway
│       └── frontend/             # CloudFront
├── services/
│   ├── order-service/            # Python Flask on ECS Fargate
│   ├── inventory-service/        # Go on EKS
│   ├── loyalty-service/          # Java Spring Boot on EC2
│   ├── menu-service/             # Node.js Express on EKS
│   ├── payment-processor/        # Python Lambda
│   └── analytics-worker/         # Python on EC2
├── chaos/
│   ├── scenarios/                # Individual chaos scripts
│   ├── lib/                      # Shared functions
│   └── master-chaos.sh           # Orchestrator
├── load-testing/
│   └── k6/scenarios/             # Load test scripts
├── scripts/
│   ├── deploy-all.sh             # One-command deployment
│   └── validate-infrastructure.sh # Validation script
└── dashboard_full.json           # CloudWatch dashboard definition
```

## 💰 Cost Estimate

**Monthly cost (development environment): ~$800-1200**

Breakdown:
- **Compute:** $300 (ECS Fargate + EKS + EC2)
- **Databases:** $200 (RDS Aurora + DocumentDB)
- **Redshift:** $180 (single-node ra3.xlarge)
- **ElastiCache/MemoryDB:** $100
- **Data Transfer:** $50
- **Other:** $170 (ALB, NLB, API Gateway, Lambda, SQS, Kinesis)

### Cost Optimization

- Use `terraform destroy` when not testing
- Redshift: Pause cluster when not in use
- EKS: Use spot instances for node groups
- Lambda: Stay within free tier (1M requests/month)
- DynamoDB: Use on-demand billing for dev

## 🔧 Configuration

### Environment Variables

**Order Service (ECS):**
```bash
DB_HOST=<rds-endpoint>
DB_PORT=5432
DB_NAME=cloudcafe
DB_USER=cloudcafe_admin
DB_PASSWORD=<from-secrets-manager>
REDIS_HOST=<elasticache-endpoint>
KINESIS_ORDER_EVENTS_STREAM=cloudcafe-order-events-dev
DYNAMODB_ACTIVE_ORDERS_TABLE=cloudcafe-active-orders-dev
AWS_REGION=us-east-1
```

### Terraform Variables

Override in `infrastructure/terraform/terraform.tfvars`:

```hcl
aws_region = "us-east-1"
project_name = "cloudcafe"
environment = "dev"
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
```

## 🧪 Testing & Validation

### Validation Checklist

Run `scripts/validate-infrastructure.sh` to verify:

- ✅ All 17 AWS services deployed
- ✅ CloudWatch metrics emitting for each service
- ✅ Services accessible and healthy
- ✅ Auto-scaling configured correctly
- ✅ Security groups properly configured

### Manual Testing

```bash
# Test order creation
curl -X POST http://<alb-endpoint>/api/orders \
  -H "Content-Type: application/json" \
  -d '{
    "customer_id": "user-123",
    "store_id": 1,
    "items": [{"item_id": "latte", "quantity": 2, "price": 5.0}]
  }'

# Test order retrieval
curl http://<alb-endpoint>/api/orders/<order-id>

# Test menu service
curl http://<alb-endpoint>/api/menu/items
```

## 📚 Additional Resources

### Architecture Diagram
See `dashboard_full.json` for comprehensive CloudWatch dashboard configuration.

### Database Schema

**RDS (PostgreSQL):**
```sql
CREATE TABLE orders (
    order_id VARCHAR(255) PRIMARY KEY,
    customer_id VARCHAR(255) NOT NULL,
    store_id VARCHAR(255) NOT NULL,
    total_amount DECIMAL(10,2),
    status VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_customer_orders ON orders(customer_id, created_at);
```

**DynamoDB Tables:**
- `cloudcafe-active-orders-dev` (PK: order_id, GSI: customer_id+created_at)
- `cloudcafe-menu-catalog-dev` (PK: item_id, GSI: category)
- `cloudcafe-store-inventory-dev` (PK: store_id, SK: sku)

### Service Dependencies

```
CloudFront → API Gateway → ALB → {
    ECS (Order Service) → RDS, DynamoDB, Kinesis
    EKS (Inventory Service) → DynamoDB, MemoryDB
    EKS (Menu Service) → DocumentDB, ElastiCache
}
EC2 (Loyalty Service) → RDS, Redshift
Lambda (Payment Processor) → SQS, DynamoDB
EC2 (Analytics Worker) → Kinesis, Redshift
```

## 🐛 Troubleshooting

### Common Issues

**Issue:** Terraform fails with "VPC limit exceeded"
**Solution:** Delete unused VPCs or request limit increase

**Issue:** ECS tasks fail to start
**Solution:** Check CloudWatch logs, verify security group rules

**Issue:** Cannot connect to RDS
**Solution:** Verify security group allows PostgreSQL (5432) from compute SGs

**Issue:** ElastiCache flush script fails
**Solution:** Ensure redis-cli is installed and you're running from within VPC

**Issue:** Chaos scripts fail with "Terraform output not found"
**Solution:** Run `terraform apply` first to deploy infrastructure

### Debug Commands

```bash
# View ECS task logs
aws logs tail /ecs/cloudcafe-order-service --follow

# Check EKS pod status
kubectl get pods --all-namespaces
kubectl describe pod <pod-name>

# View RDS cluster status
aws rds describe-db-clusters --db-cluster-identifier cloudcafe-aurora-dev

# Check DynamoDB table
aws dynamodb describe-table --table-name cloudcafe-active-orders-dev

# Monitor SQS queue
aws sqs get-queue-attributes \
  --queue-url <queue-url> \
  --attribute-names All
```

## 🤝 Contributing

This is a demonstration project. For production use:

1. Add authentication/authorization
2. Implement proper secret management (AWS Secrets Manager)
3. Add WAF rules and DDoS protection
4. Implement backup strategies
5. Add comprehensive monitoring and alerting
6. Implement CI/CD pipelines
7. Add comprehensive unit and integration tests

## 📄 License

MIT License - See LICENSE file for details

## 🎓 Learning Objectives

This project demonstrates:

- ✅ Multi-service AWS architecture
- ✅ Infrastructure as Code with Terraform
- ✅ Polyglot microservices
- ✅ Chaos engineering practices
- ✅ CloudWatch observability
- ✅ Auto-scaling and resilience patterns
- ✅ Database selection and optimization
- ✅ Caching strategies
- ✅ Event-driven architecture
- ✅ Load testing methodologies

## 📞 Support

For questions or issues:
1. Check the troubleshooting section
2. Review CloudWatch logs
3. Verify Terraform outputs
4. Check service health endpoints

---

**Built with ❤️ for demonstrating AWS best practices and chaos engineering**
