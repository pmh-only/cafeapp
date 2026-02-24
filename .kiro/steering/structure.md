---
inclusion: auto
---

# Project Structure

## Top-Level Organization

```
cafeapp/
├── infrastructure/terraform/    # All IaC definitions
├── services/                    # Microservices (6 services)
├── chaos/                       # Chaos engineering scripts
├── load-testing/                # K6 load test scenarios
├── scripts/                     # Deployment and validation scripts
└── *.md                         # Documentation files
```

## Infrastructure (`infrastructure/terraform/`)

Terraform modules organized by AWS service category:

- `main.tf` - Root module orchestrating all infrastructure
- `variables.tf` - Global configuration variables
- `outputs.tf` - Resource ARNs and endpoints for services
- `modules/networking/` - VPC, subnets, security groups, NAT
- `modules/databases/` - RDS Aurora, DynamoDB, DocumentDB, Redshift
- `modules/caching/` - ElastiCache Redis, MemoryDB
- `modules/compute/` - EC2 Auto Scaling, ECS, EKS clusters
- `modules/loadbalancing/` - ALB, NLB, VPC Lattice
- `modules/messaging/` - SQS queues, Kinesis streams
- `modules/serverless/` - Lambda functions, API Gateway
- `modules/frontend/` - CloudFront distribution

Each module follows standard structure: `main.tf`, `variables.tf`, `outputs.tf`

## Services (`services/`)

Six polyglot microservices, each self-contained:

### Order Service (Python/ECS)
```
order-service/
├── app/                 # Application code
├── Dockerfile          # Container definition
└── requirements.txt    # Python dependencies
```

### Inventory Service (Go/EKS)
```
inventory-service/
├── cmd/main.go         # Entry point
├── pkg/stress/         # Stress scenario logic
├── k8s/deployment.yaml # Kubernetes manifests
├── Dockerfile
└── go.mod
```

### Menu Service (Node.js/EKS)
```
menu-service/
├── src/                # Source code
├── k8s/deployment.yaml # Kubernetes manifests
├── Dockerfile
└── package.json
```

### Loyalty Service (Java/EC2)
```
loyalty-service/
├── src/main/java/com/cloudcafe/  # Java source
│   ├── controller/               # REST controllers
│   ├── service/                  # Business logic
│   ├── model/                    # Data models
│   └── repository/               # Data access
├── src/main/resources/           # Configuration
├── pom.xml                       # Maven dependencies
└── deploy-ec2.sh                 # Deployment script
```

### Payment Processor (Lambda)
```
payment-processor/
├── handler.py          # Lambda handler
├── requirements.txt
└── deploy.sh
```

### Analytics Worker (EC2)
```
analytics-worker/
├── worker.py           # Kinesis consumer
├── requirements.txt
└── deploy-ec2.sh
```

## Chaos Engineering (`chaos/`)

```
chaos/
├── master-chaos.sh              # Orchestrates all scenarios
└── scenarios/                   # Individual chaos scripts
    ├── 01-alb-routing-failure.sh
    ├── 03-rds-failover.sh
    ├── 04-dynamodb-throttle.sh
    ├── 05-elasticache-flush.sh
    ├── 06-ecs-task-kill.sh
    └── 07-eks-node-drain.sh
```

## Load Testing (`load-testing/`)

```
load-testing/
└── k6/scenarios/
    └── morning-rush.js    # K6 load test script
```

## Scripts (`scripts/`)

Utility scripts for deployment and operations:

- `deploy-all.sh` - One-command full deployment
- `validate-infrastructure.sh` - Post-deployment validation
- `init-rds-schema.sql` - Database schema initialization

## Key Documentation Files

- `README.md` - Comprehensive project documentation
- `ARCHITECTURE.md` - Detailed architecture and design decisions
- `QUICKSTART.md` - Step-by-step deployment guide
- `dashboard_full.json` - CloudWatch dashboard definition

## Naming Conventions

- **Resources:** `cloudcafe-<service>-<environment>` (e.g., `cloudcafe-order-service-dev`)
- **DynamoDB tables:** `cloudcafe-<purpose>-<environment>` (e.g., `cloudcafe-active-orders-dev`)
- **Security groups:** `<service>-sg` (e.g., `ecs-task-sg`)
- **IAM roles:** `cloudcafe-<service>-role-<environment>`
- **Log groups:** `/ecs/cloudcafe-<service>` or `/aws/<service>/cloudcafe/`

## Configuration Files

- Terraform variables: `infrastructure/terraform/terraform.tfvars` (create if needed)
- Service configs: Environment variables in Terraform or Kubernetes manifests
- Secrets: AWS Secrets Manager (referenced in Terraform outputs)
