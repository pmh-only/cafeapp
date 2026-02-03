# CloudCafe Architecture

## System Overview

CloudCafe is a cloud-native, microservices-based coffee ordering platform designed to demonstrate AWS best practices, chaos engineering, and comprehensive observability.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Internet Users                          │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                    ┌───────────▼──────────┐
                    │    CloudFront CDN    │
                    │   (Global Edge)      │
                    └───────────┬──────────┘
                                │
                    ┌───────────▼──────────┐
                    │    API Gateway       │
                    │  (REST API Layer)    │
                    └───────────┬──────────┘
                                │
                    ┌───────────▼──────────┐
                    │ Application LB (ALB) │
                    │ (Path-based routing) │
                    └───────┬───┬───┬──────┘
                            │   │   │
        ┌───────────────────┘   │   └──────────────────┐
        │                       │                       │
┌───────▼────────┐    ┌────────▼────────┐    ┌────────▼────────┐
│   ECS Fargate  │    │   EKS Cluster   │    │ EC2 Auto Scaling│
│ Order Service  │    │ Inventory/Menu  │    │ Loyalty Service │
│   (Python)     │    │   (Go/Node.js)  │    │     (Java)      │
└───────┬────────┘    └────────┬────────┘    └────────┬────────┘
        │                      │                       │
        │          ┌───────────┴──────────┐           │
        │          │   VPC Lattice        │           │
        │          │ Service-to-Service   │           │
        │          └──────────────────────┘           │
        │                                              │
    ┌───▼────────────────────────────────────────────▼───┐
    │                   Data Layer                       │
    │                                                     │
    │  ┌──────────┐  ┌──────────┐  ┌──────────┐        │
    │  │   RDS    │  │ DynamoDB │  │DocumentDB│        │
    │  │ Aurora   │  │ (3 tables)│  │  (Mongo) │        │
    │  │PostgreSQL│  └──────────┘  └──────────┘        │
    │  └──────────┘                                      │
    │                                                     │
    │  ┌──────────┐  ┌──────────┐  ┌──────────┐        │
    │  │ElastiCache│  │ MemoryDB │  │ Redshift │        │
    │  │  (Redis) │  │  (Redis) │  │Analytics │        │
    │  └──────────┘  └──────────┘  └──────────┘        │
    └─────────────────────────────────────────────────────┘
                          │
        ┌─────────────────┴─────────────────┐
        │                                   │
┌───────▼────────┐              ┌───────────▼─────────┐
│      SQS       │              │   Kinesis Streams   │
│   (3 queues)   │              │ (order/analytics)   │
└───────┬────────┘              └───────────┬─────────┘
        │                                   │
┌───────▼────────┐              ┌───────────▼─────────┐
│    Lambda      │              │   EC2 Analytics     │
│  Payment       │              │      Worker         │
│  Processor     │              │  (Kinesis→Redshift) │
└────────────────┘              └─────────────────────┘
```

## Service Details

### 1. Order Service (Python Flask on ECS Fargate)

**Purpose:** Core order management - creation, retrieval, status updates

**Technology Stack:**
- Python 3.11
- Flask web framework
- Gunicorn WSGI server
- psycopg2 (PostgreSQL client)
- boto3 (AWS SDK)
- redis-py

**Data Access:**
- **Primary:** DynamoDB `active-orders` table (hot data, 24hr TTL)
- **Secondary:** RDS Aurora PostgreSQL (persistent storage)
- **Cache:** ElastiCache Redis (session cache)
- **Events:** Kinesis `order-events` stream

**Key Endpoints:**
- `POST /orders` - Create new order
- `GET /orders/:id` - Retrieve order details
- `POST /stress/morning-rush` - Trigger CPU stress scenario

**Deployment:**
- ECS Fargate task (1 vCPU, 2 GB RAM)
- Auto-scaling: 2-10 tasks based on CPU (70% target)
- Health check: `/health` endpoint
- Container Insights enabled

**Stress Scenario - Morning Rush:**
```python
# CPU-intensive operations:
# - Complex order validation (JSON processing)
# - Fraud scoring (SHA256 hashing)
# - Inventory checks (Fibonacci calculations)
# - Tax calculations (floating point ops)
# Target: 95% CPU for 5 minutes
```

### 2. Inventory Service (Go on EKS)

**Purpose:** Real-time store inventory management

**Technology Stack:**
- Go 1.21
- Native HTTP server
- AWS SDK for Go v2
- Redis client (go-redis)

**Data Access:**
- **Primary:** DynamoDB `store-inventory` table
- **Cache:** MemoryDB for Redis (atomic counters)
- **Sync:** DynamoDB Streams → Lambda triggers

**Key Endpoints:**
- `GET /inventory/store/:id` - Get store inventory
- `POST /inventory/update` - Update inventory levels
- `POST /stress/restock` - Trigger restock storm

**Deployment:**
- Kubernetes Deployment (3 replicas)
- Resource limits: 1 CPU, 1 GB RAM
- HPA: Scale 3-10 pods based on CPU (80% target)
- Service type: LoadBalancer

**Stress Scenario - Restock Storm:**
```go
// CPU-intensive operations:
// - Hash calculations for 10K SKUs
// - JSON marshaling/unmarshaling
// - Concurrent goroutines per store
// Target: 80% CPU for 3 minutes
```

### 3. Menu Service (Node.js Express on EKS)

**Purpose:** Menu catalog and customization

**Technology Stack:**
- Node.js 20
- Express.js framework
- AWS SDK for JavaScript v3
- mongoose (MongoDB ODM)
- ioredis

**Data Access:**
- **Primary:** DocumentDB `menu_configs` collection
- **Cache:** ElastiCache Redis (5-minute TTL)
- **CDN:** CloudFront (static assets)

**Key Endpoints:**
- `GET /menu/items` - List menu items
- `GET /menu/items/:category` - Category filter
- `POST /menu/sync` - Trigger menu sync (stress)

**Deployment:**
- Kubernetes Deployment (3 replicas)
- Resource limits: 500m CPU, 512 MB RAM
- ConfigMap: Menu configuration
- Secret: DocumentDB credentials

**Stress Scenario - Menu Sync Storm:**
```javascript
// CPU-intensive operations:
// - Sync 10K menu items with images
// - SHA256 hash validation
// - JSON processing for each item
// Target: 70% CPU for 3 minutes
```

### 4. Loyalty Service (Java Spring Boot on EC2)

**Purpose:** Customer loyalty points and tier management

**Technology Stack:**
- Java 17 (Amazon Corretto)
- Spring Boot 3.x
- Spring Data JPA
- HikariCP connection pool
- AWS SDK for Java 2.x

**Data Access:**
- **Primary:** RDS Aurora PostgreSQL `users` table
- **Analytics:** Redshift (aggregated loyalty data)
- **Queue:** SQS for async updates

**Key Endpoints:**
- `GET /loyalty/points/:userId` - Get user points
- `POST /loyalty/accrue` - Accrue points from order
- `POST /stress/batch-calculation` - Trigger hourly batch

**Deployment:**
- EC2 Auto Scaling Group
- Instance type: t3.large
- Scaling: 2-10 instances (CPU 70% target)
- Behind Network Load Balancer (NLB)
- CloudWatch agent for detailed metrics

**Stress Scenario - Batch Calculation:**
```java
// CPU-intensive operations:
// - Process 10M customer records
// - Complex tier calculations
// - Multi-threaded processing
// - SHA256 hashing for audit trail
// Target: 100% CPU for 12 minutes (hourly job)
```

### 5. Payment Processor (Python Lambda)

**Purpose:** Asynchronous payment processing

**Technology Stack:**
- Python 3.11
- boto3 (AWS SDK)
- Triggered by SQS FIFO queue
- DynamoDB for transaction log

**Event Flow:**
1. Order service publishes to `payment-processing-queue.fifo`
2. Lambda triggered (batch size: 10, window: 5s)
3. Process payments (mock Stripe/Square API)
4. Write transaction to DynamoDB
5. Publish result to SNS topic

**Deployment:**
- Memory: 512 MB
- Timeout: 30 seconds
- Reserved concurrency: 100
- DLQ: Automatic retry 3x

**Stress Scenario - Cold Start Avalanche:**
```python
# Simulate Black Friday:
# - 10K concurrent executions
# - All cold starts (3s delay)
# - CPU-intensive fraud validation
# Target: 3000ms p99 duration
```

### 6. Analytics Worker (Python on EC2)

**Purpose:** Real-time analytics pipeline

**Technology Stack:**
- Python 3.11
- Kinesis consumer (KCL 2.x)
- psycopg2 (PostgreSQL/Redshift)
- pandas for data transformation

**Data Flow:**
1. Consume from `analytics-events` Kinesis stream
2. Aggregate events (1-minute windows)
3. Transform to OLAP schema
4. Batch insert to Redshift

**Deployment:**
- EC2 instance: t3.large
- Systemd service (auto-restart)
- CloudWatch Logs agent
- Single instance (stateful KCL checkpointing)

**Stress Scenario - Query Storm:**
```python
# End-of-quarter reports:
# - 500 concurrent Redshift queries
# - Large result sets (100K+ rows)
# - CPU for data processing
# Target: 90% Redshift CPU, high query duration
```

## Data Architecture

### Database Selection Matrix

| Service | Database | Use Case | Rationale |
|---------|----------|----------|-----------|
| Order | RDS Aurora PostgreSQL | Transactional orders | ACID, relationships, SQL |
| Order | DynamoDB | Active orders cache | Low latency, TTL, auto-scale |
| Menu | DocumentDB | Menu configurations | Flexible schema, JSON |
| Inventory | DynamoDB | Real-time stock levels | High throughput, atomic updates |
| Loyalty | RDS Aurora PostgreSQL | User profiles, points | Complex queries, transactions |
| Analytics | Redshift | Historical analysis | Columnar storage, OLAP |

### Caching Strategy

**ElastiCache (Redis):**
- **Menu items:** 5-minute TTL
- **User sessions:** 30-minute TTL
- **Store metadata:** 1-hour TTL
- **Eviction policy:** LRU

**MemoryDB (Redis):**
- **Inventory counters:** Real-time atomic operations
- **Store status:** Durable, sub-ms latency
- **Rate limiting:** Token bucket counters

### Message Queues

**SQS Queues:**
1. `order-submission-queue` (Standard)
   - Order validation before processing
   - Long polling: 20s

2. `payment-processing-queue` (FIFO)
   - Exactly-once processing
   - Message group ID: `customer_id`
   - Deduplication: Content-based

3. `notification-queue` (Standard)
   - Email/SMS notifications
   - Fan-out from SNS topic

**Kinesis Streams:**
1. `order-events` (4 shards)
   - Real-time order events
   - Partition key: `customer_id`
   - Retention: 24 hours

2. `analytics-events` (2 shards)
   - Aggregated analytics
   - Partition key: `store_id`
   - Retention: 24 hours

## Network Architecture

### VPC Design

**CIDR:** 10.0.0.0/16

**Subnets (per AZ):**
- Public subnet: 10.0.{1-3}.0/24 (ALB, NAT)
- Private subnet: 10.0.{11-13}.0/24 (compute)
- Database subnet: 10.0.{21-23}.0/24 (RDS, ElastiCache)

**Availability Zones:** us-east-1a, us-east-1b, us-east-1c

**NAT Strategy:** Single NAT Gateway (cost optimization)

### Security Groups

| SG Name | Inbound Rules | Used By |
|---------|---------------|---------|
| alb-sg | 80/443 from 0.0.0.0/0 | ALB |
| ecs-task-sg | 8080 from ALB | ECS tasks |
| eks-node-sg | 8080 from ALB, all from VPC | EKS nodes |
| ec2-sg | 8080 from NLB, 22 from VPC | EC2 instances |
| rds-sg | 5432 from compute SGs | RDS Aurora |
| elasticache-sg | 6379 from compute SGs | ElastiCache/MemoryDB |
| redshift-sg | 5439 from EC2 SG | Redshift |

### Load Balancing

**Application Load Balancer (ALB):**
- **Scheme:** Internet-facing
- **Listeners:** HTTP:80, HTTPS:443
- **Target Groups:**
  - `order-service-tg` → ECS tasks
  - `menu-service-tg` → EKS pods
  - `inventory-service-tg` → EKS pods
- **Routing Rules:**
  - `/api/orders/*` → order-service
  - `/api/menu/*` → menu-service
  - `/api/inventory/*` → inventory-service

**Network Load Balancer (NLB):**
- **Scheme:** Internal
- **Listeners:** TCP:8080
- **Target Group:** `loyalty-service-tg` → EC2 instances
- **Use Case:** Service-to-service communication

**VPC Lattice Service Network:**
- **Services:** order-service, inventory-service
- **Consumers:** EKS pods
- **Benefits:** Service discovery, mTLS, observability

## Observability

### CloudWatch Metrics

**Custom Application Metrics:**
- `CloudCafe/OrderService/CPUStressLevel`
- `CloudCafe/OrderService/OrderCreationDuration`
- `CloudCafe/Inventory/RestockCPU`
- `CloudCafe/Menu/SyncCPU`
- `CloudCafe/Loyalty/BatchJobCPU`

**AWS Service Metrics:**
- ECS: `CPUUtilization`, `MemoryUtilization`, `RunningTaskCount`
- EKS: `pod_cpu_utilization`, `pod_memory_utilization`
- RDS: `DatabaseConnections`, `CPUUtilization`, `ReadLatency`
- DynamoDB: `ConsumedReadCapacityUnits`, `UserErrors`
- Lambda: `Duration`, `Errors`, `ConcurrentExecutions`
- Kinesis: `IncomingRecords`, `GetRecords.IteratorAgeMilliseconds`

### Logging Strategy

**CloudWatch Log Groups:**
- `/ecs/cloudcafe-order-service`
- `/aws/eks/cloudcafe/cluster`
- `/aws/lambda/cloudcafe-payment-processor`
- `/aws/rds/cluster/cloudcafe-aurora/postgresql`

**Log Retention:** 7 days (dev), 30 days (prod)

**Structured Logging:**
```json
{
  "timestamp": "2024-01-01T12:00:00Z",
  "level": "INFO",
  "service": "order-service",
  "trace_id": "abc123",
  "customer_id": "user-456",
  "message": "Order created successfully"
}
```

### Alarms (Production)

1. **High Error Rate:** ALB 5XX > 5% for 5 minutes
2. **Database Connections:** RDS connections > 80% for 10 minutes
3. **DynamoDB Throttling:** UserErrors > 100 for 5 minutes
4. **Lambda Errors:** Error rate > 2% for 5 minutes
5. **ECS Task Count:** Running tasks < desired for 3 minutes
6. **Cache Hit Rate:** ElastiCache hit rate < 70% for 15 minutes

## Chaos Engineering

### Failure Scenarios

**Network Failures:**
- ALB routing rule deletion
- Security group ingress revocation
- NAT Gateway failure simulation

**Compute Failures:**
- ECS task termination (50% capacity loss)
- EKS node drain
- EC2 instance termination
- Lambda throttling

**Database Failures:**
- RDS Aurora failover
- DynamoDB capacity throttling
- DocumentDB connection exhaustion

**Cache Failures:**
- ElastiCache flush (cache miss storm)
- MemoryDB restart
- Redis eviction pressure

### Recovery Mechanisms

| Failure Type | Recovery Mechanism | Expected Duration |
|--------------|-------------------|-------------------|
| ECS task kill | ECS auto-recovery | 60-90 seconds |
| RDS failover | Aurora automatic failover | 30-60 seconds |
| Cache flush | Application cache rebuild | 5-10 minutes |
| ALB rules deleted | Terraform re-apply | Manual |
| DynamoDB throttle | Auto-scaling (if enabled) | 2-5 minutes |
| Lambda cold start | Concurrent execution ramp | Gradual |

## Cost Optimization

### Resource Right-Sizing

**Compute:**
- ECS: Use Fargate Spot for non-critical tasks (70% savings)
- EKS: Use spot instances for node group (60% savings)
- Lambda: Optimize memory allocation (128MB → 256MB if needed)

**Databases:**
- RDS: Use Graviton instances (db.r6g vs db.r6i: 20% savings)
- DynamoDB: On-demand billing for unpredictable workloads
- Redshift: Pause cluster when not in use

**Caching:**
- ElastiCache: Use t3 instances for dev
- MemoryDB: Start with 1 shard, scale as needed

### Cost Monitoring

**Daily Budget:** ~$30-40/day
- Compute: ~$15/day
- Databases: ~$10/day
- Other: ~$5-15/day

**Monthly Estimate:** ~$800-1200

## Security Best Practices

### IAM Policies

**Principle of Least Privilege:**
- ECS task role: DynamoDB, Kinesis, CloudWatch only
- Lambda execution role: SQS, DynamoDB only
- EC2 instance role: Systems Manager, CloudWatch only

### Secrets Management

**AWS Secrets Manager:**
- RDS passwords: Auto-rotation every 30 days
- DocumentDB passwords: Auto-rotation every 30 days
- API keys: Stored as SecureString parameters

### Network Security

**Encryption:**
- Data in transit: TLS 1.2+ for all connections
- Data at rest: KMS encryption for databases
- ElastiCache: In-transit encryption enabled
- MemoryDB: TLS required

**Compliance:**
- VPC Flow Logs enabled
- CloudTrail for API audit
- Config for compliance checks

## Disaster Recovery

### Backup Strategy

**RDS Aurora:**
- Automated backups: 7-day retention
- Manual snapshots: Before major deployments
- Cross-region replica: Production only

**DynamoDB:**
- Point-in-time recovery (PITR) enabled
- On-demand backups before schema changes

**Redshift:**
- Automated snapshots: 1-day retention
- Manual snapshots: Weekly

### RTO/RPO Targets

| Tier | RTO | RPO | Strategy |
|------|-----|-----|----------|
| Critical (Orders, Payments) | 1 hour | 5 minutes | Multi-AZ, automated failover |
| Important (Inventory, Menu) | 4 hours | 15 minutes | Backups, manual recovery |
| Low (Analytics) | 24 hours | 1 day | Snapshots, rebuild from source |

---

**Architecture Version:** 1.0
**Last Updated:** 2024
**Infrastructure as Code:** Terraform 1.5+
**Cloud Provider:** AWS
