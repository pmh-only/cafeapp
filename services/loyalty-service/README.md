# Loyalty Service (Java Spring Boot)

Customer loyalty points management service built with Spring Boot, deployed on Amazon EC2 with Auto Scaling.

## Technology Stack

- **Runtime:** Java 17 (Amazon Corretto)
- **Framework:** Spring Boot 3.2.1
- **Database:** RDS Aurora PostgreSQL
- **Analytics:** Amazon Redshift
- **Deployment:** Amazon EC2 with Auto Scaling

## Features

- Customer loyalty account management
- Points accrual from orders with tier multipliers
- Automatic tier upgrades (Bronze → Silver → Gold → Platinum)
- Points redemption
- Analytics integration with Redshift
- Built-in CPU stress scenario (Batch Calculation)
- CloudWatch custom metrics
- Auto-scaling based on CPU load

## API Endpoints

### Health Check
```
GET /loyalty/health
```

Response:
```json
{
  "status": "healthy",
  "service": "loyalty-service",
  "timestamp": "2024-01-01T12:00:00Z",
  "database": {
    "connected": true,
    "account_count": 1500000
  }
}
```

### Get Loyalty Points
```
GET /loyalty/points/{customerId}
```

Response:
```json
{
  "customer_id": "user-12345",
  "points_balance": 2500,
  "lifetime_points": 8750,
  "tier": "GOLD",
  "tier_multiplier": 2.0,
  "last_purchase_date": "2024-01-01T10:30:00Z",
  "duration_ms": 45
}
```

### Accrue Points
```
POST /loyalty/accrue
Content-Type: application/json

{
  "customer_id": "user-12345",
  "order_id": "order-98765",
  "order_amount": 45.50
}
```

Response:
```json
{
  "customer_id": "user-12345",
  "points_earned": 91,
  "new_balance": 2591,
  "lifetime_points": 8841,
  "tier": "GOLD",
  "tier_changed": false,
  "duration_ms": 120
}
```

### Redeem Points
```
POST /loyalty/redeem
Content-Type: application/json

{
  "customer_id": "user-12345",
  "points": 500
}
```

### Get Tier Statistics
```
GET /loyalty/stats/tiers
```

Response:
```json
{
  "BRONZE": {
    "count": 800000,
    "average_points": 350.5
  },
  "SILVER": {
    "count": 150000,
    "average_points": 2800.3
  },
  "GOLD": {
    "count": 45000,
    "average_points": 6500.7
  },
  "PLATINUM": {
    "count": 5000,
    "average_points": 15000.2
  },
  "total_points_outstanding": 1250000000
}
```

### Trigger Stress Scenario
```
POST /loyalty/stress/batch-calculation
Content-Type: application/json

{
  "duration_seconds": 720,
  "target_cpu": 100
}
```

## Stress Scenario: Loyalty Batch Calculation

**Story:** Every hour, the loyalty service recalculates points, tiers, and rewards for all 10 million customers. This CPU-intensive batch job processes complex tier multipliers, purchase history analysis, and fraud detection scoring.

**CPU-Intensive Operations:**
- Complex tier multiplier calculations (floating point)
- Purchase bonus with exponential decay
- Fraud scoring with extensive hash operations (SHA256, MD5)
- Fibonacci calculations for bonus algorithms
- Multi-threaded parallel processing

**Expected Impact:**
- EC2 CPU → 100% (all cores)
- RDS read IOPS spike
- Redshift concurrent queries increase
- EC2 Auto Scaling triggers (adds instances)
- NLB connection count increases

**Duration:** 12 minutes (default)

## Loyalty Tiers

| Tier | Lifetime Points | Multiplier |
|------|----------------|------------|
| Bronze | 0 - 999 | 1.0x |
| Silver | 1,000 - 4,999 | 1.5x |
| Gold | 5,000 - 9,999 | 2.0x |
| Platinum | 10,000+ | 2.5x |

**Example:**
- Order amount: $50.00
- Bronze customer: 50 points (1.0x)
- Silver customer: 75 points (1.5x)
- Gold customer: 100 points (2.0x)
- Platinum customer: 125 points (2.5x)

## Build & Deploy

### Local Development

```bash
# Install Java 17
# On macOS: brew install openjdk@17
# On Ubuntu: sudo apt install openjdk-17-jdk

# Set JAVA_HOME
export JAVA_HOME=/path/to/java-17

# Build with Maven
mvn clean package

# Set environment variables
export DB_HOST=localhost
export DB_NAME=cloudcafe
export DB_USER=postgres
export DB_PASSWORD=password
export ENVIRONMENT=dev

# Run locally
java -jar target/loyalty-service.jar

# Or use Spring Boot Maven plugin
mvn spring-boot:run

# Test
curl http://localhost:8080/loyalty/health
```

### Deploy to EC2

#### Option 1: User Data (Launch Template)

Add this to EC2 Launch Template User Data:

```bash
#!/bin/bash
cd /home/ec2-user
git clone https://github.com/yourorg/cloudcafe.git
cd cloudcafe/services/loyalty-service
./deploy-ec2.sh
```

#### Option 2: Manual Deployment

```bash
# SSH to EC2 instance
ssh -i your-key.pem ec2-user@<ec2-ip>

# Copy source code
scp -r loyalty-service/ ec2-user@<ec2-ip>:/home/ec2-user/

# Run deployment script
cd /home/ec2-user/loyalty-service
./deploy-ec2.sh
```

#### Option 3: AWS Systems Manager

```bash
# Create SSM document for deployment
aws ssm create-document \
  --name "DeployLoyaltyService" \
  --document-type "Command" \
  --content file://deploy-ssm-document.json

# Run command on Auto Scaling Group instances
aws ssm send-command \
  --document-name "DeployLoyaltyService" \
  --targets "Key=tag:aws:autoscaling:groupName,Values=loyalty-service-asg"
```

### Build Docker Image (Optional)

```bash
# Create Dockerfile
cat > Dockerfile <<EOF
FROM amazoncorretto:17-alpine
WORKDIR /app
COPY target/loyalty-service.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
EOF

# Build image
docker build -t loyalty-service .

# Run container
docker run -p 8080:8080 \
  -e DB_HOST=localhost \
  -e DB_PASSWORD=password \
  loyalty-service
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `SERVER_PORT` | HTTP server port | `8080` |
| `DB_HOST` | RDS Aurora endpoint | `localhost` |
| `DB_NAME` | Database name | `cloudcafe` |
| `DB_USER` | Database username | `postgres` |
| `DB_PASSWORD` | Database password | - |
| `ENVIRONMENT` | Environment name | `dev` |
| `REDSHIFT_CLUSTER_ID` | Redshift cluster ID | `cloudcafe-redshift-dev` |
| `REDSHIFT_DATABASE` | Redshift database | `analytics` |
| `REDSHIFT_DB_USER` | Redshift username | `admin` |
| `AWS_REGION` | AWS region | `us-east-1` |

## Database Schema

The service automatically creates tables via JPA/Hibernate:

```sql
CREATE TABLE loyalty_accounts (
    id BIGSERIAL PRIMARY KEY,
    customer_id VARCHAR(100) UNIQUE NOT NULL,
    points_balance INTEGER NOT NULL DEFAULT 0,
    lifetime_points INTEGER NOT NULL DEFAULT 0,
    tier VARCHAR(20) NOT NULL DEFAULT 'BRONZE',
    tier_multiplier DOUBLE PRECISION NOT NULL DEFAULT 1.0,
    last_purchase_date TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_customer_id ON loyalty_accounts(customer_id);
CREATE INDEX idx_tier ON loyalty_accounts(tier);
```

## Monitoring

### CloudWatch Metrics

Custom metrics in `CloudCafe/Loyalty` namespace:

- `QueryDuration` - Database query latency
- `PointsRetrieved` / `PointsAccrued` / `PointsRedeemed` - Transaction counts
- `TierUpgrade` - Customer tier upgrade events
- `AccountNotFound` / `QueryError` / `AccrualError` / `RedemptionError` - Error counts
- `BatchJobCPU` - CPU usage during batch job
- `BatchJobIterations` - Batch job progress
- `BatchJobCompleted` - Batch job completion

### EC2 Metrics

Standard EC2 metrics available in CloudWatch:

```bash
# View CPU utilization
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=AutoScalingGroupName,Value=loyalty-service-asg \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T23:59:59Z \
  --period 300 \
  --statistics Average
```

### Auto Scaling Events

```bash
# View scaling activity
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name loyalty-service-asg \
  --max-records 20
```

### Application Logs

```bash
# View service logs
sudo journalctl -u loyalty-service -f

# View CloudWatch Logs
aws logs tail /cloudcafe/loyalty-service --follow
```

## Performance Testing

### Load Test with Apache Bench

```bash
# Test health endpoint
ab -n 10000 -c 100 http://<nlb-dns>/loyalty/health

# Test points retrieval
ab -n 5000 -c 50 http://<nlb-dns>/loyalty/points/user-12345

# Test points accrual
ab -n 1000 -c 20 -p accrual.json -T application/json \
  http://<nlb-dns>/loyalty/accrue
```

### Trigger Batch Calculation

```bash
# 12-minute batch job at 100% CPU
curl -X POST http://<nlb-dns>/loyalty/stress/batch-calculation \
  -H "Content-Type: application/json" \
  -d '{"duration_seconds": 720, "target_cpu": 100}'

# Monitor CPU usage
watch -n 5 'aws cloudwatch get-metric-statistics \
  --namespace CloudCafe/Loyalty \
  --metric-name BatchJobCPU \
  --start-time $(date -u -d "5 minutes ago" +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Average \
  --query "Datapoints[*].[Timestamp,Average]" \
  --output table'
```

## Troubleshooting

### Service Won't Start

**Symptoms:**
- `systemctl status loyalty-service` shows failed
- Application exits immediately

**Solutions:**
```bash
# Check logs for errors
sudo journalctl -u loyalty-service -n 100

# Verify Java installation
java -version

# Check database connectivity
psql -h $DB_HOST -U $DB_USER -d $DB_NAME

# Verify environment variables
sudo systemctl show loyalty-service | grep Environment
```

### High Database Connection Count

**Symptoms:**
- RDS connections near max_connections limit
- "Too many connections" errors

**Solutions:**
```bash
# Check current connections
psql -h $DB_HOST -U $DB_USER -d $DB_NAME \
  -c "SELECT count(*) FROM pg_stat_activity WHERE datname='cloudcafe';"

# Reduce connection pool size in application.properties
spring.datasource.hikari.maximum-pool-size=10

# Restart service
sudo systemctl restart loyalty-service
```

### Out of Memory

**Symptoms:**
- Java heap space errors
- EC2 instance memory > 90%

**Solutions:**
```bash
# Increase JVM heap size
sudo vi /etc/systemd/system/loyalty-service.service
# Change: JAVA_OPTS=-Xms512m -Xmx4g

# Or upgrade EC2 instance type
# t3.large (2 vCPU, 8 GB) → t3.xlarge (4 vCPU, 16 GB)
```

### Auto Scaling Not Triggering

**Symptoms:**
- CPU at 100% but no new instances launched

**Solutions:**
```bash
# Check Auto Scaling policy
aws autoscaling describe-policies \
  --auto-scaling-group-name loyalty-service-asg

# View scaling activity history
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name loyalty-service-asg

# Check CloudWatch alarm
aws cloudwatch describe-alarms \
  --alarm-names loyalty-service-cpu-high
```

## Architecture

```
┌─────────────┐
│     NLB     │
│  (Internal) │
└──────┬──────┘
       │
┌──────▼────────────────────────┐
│   EC2 Auto Scaling Group      │
│                                │
│  ┌──────────┐  ┌──────────┐  │
│  │  EC2-1   │  │  EC2-2   │  │
│  │  t3.large│  │  t3.large│  │
│  │  Java 17 │  │  Java 17 │  │
│  │  Spring  │  │  Spring  │  │
│  └─────┬────┘  └─────┬────┘  │
└────────┼─────────────┼────────┘
         │             │
    ┌────▼─────────────▼────┐
    │   RDS Aurora          │
    │   PostgreSQL          │
    │   (Primary + Replica) │
    └───────────┬───────────┘
                │
        ┌───────▼────────┐
        │   Redshift     │
        │   (Analytics)  │
        └────────────────┘
```

## License

MIT License
