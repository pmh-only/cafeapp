# Analytics Worker (Python)

Real-time analytics processing service that consumes order events from Amazon Kinesis and writes aggregated data to Amazon Redshift.

## Technology Stack

- **Runtime:** Python 3.11
- **Event Source:** Amazon Kinesis Data Streams
- **Data Warehouse:** Amazon Redshift
- **Deployment:** Amazon EC2 with Auto Scaling

## Features

- Real-time Kinesis stream consumer
- Multi-shard parallel processing
- Batch writes to Redshift via Data API
- Built-in CPU stress scenario (Query Storm)
- CloudWatch custom metrics
- Automatic error handling and retry
- Auto-scaling based on CPU load

## Architecture

The Analytics Worker acts as a bridge between real-time event streams and the data warehouse:

1. **Consume:** Reads order events from Kinesis (order-events stream)
2. **Process:** Validates and transforms events
3. **Write:** Batch inserts into Redshift fact tables
4. **Monitor:** Emits metrics to CloudWatch

```
┌─────────────────┐
│  Order Service  │
│ Inventory Svc   │
│  Payment Proc   │
└────────┬────────┘
         │ Publish events
         │
    ┌────▼────────────┐
    │  Kinesis Stream │
    │  (order-events) │
    │   4 shards      │
    └────┬────────────┘
         │ Poll
         │
    ┌────▼────────────────┐
    │  EC2 Auto Scaling   │
    │                     │
    │  ┌───────────────┐ │
    │  │  Analytics    │ │
    │  │  Worker (Py)  │ │
    │  │  - Shard 0    │ │
    │  │  - Shard 1    │ │
    │  └───────┬───────┘ │
    └──────────┼─────────┘
               │ Batch write
               │
        ┌──────▼────────┐
        │   Redshift    │
        │   Cluster     │
        │  fact_orders  │
        └───────────────┘
```

## Running the Worker

### Local Development

```bash
# Install Python 3.11
# On macOS: brew install python@3.11
# On Ubuntu: sudo apt install python3.11

# Install dependencies
pip install -r requirements.txt

# Set environment variables
export KINESIS_STREAM_NAME=order-events
export REDSHIFT_CLUSTER_ID=cloudcafe-redshift-dev
export REDSHIFT_DATABASE=analytics
export REDSHIFT_DB_USER=admin
export AWS_REGION=us-east-1
export ENVIRONMENT=dev

# Run worker
python3 worker.py

# Run with verbose logging
python3 worker.py --verbose
```

### Deploy to EC2

#### Option 1: User Data (Recommended)

Add this to EC2 Launch Template User Data:

```bash
#!/bin/bash
cd /home/ec2-user
git clone https://github.com/yourorg/cloudcafe.git
cd cloudcafe/services/analytics-worker
./deploy-ec2.sh
```

#### Option 2: Manual Deployment

```bash
# SSH to EC2 instance
ssh -i your-key.pem ec2-user@<ec2-ip>

# Copy source code
scp -r analytics-worker/ ec2-user@<ec2-ip>:/home/ec2-user/

# Run deployment script
cd /home/ec2-user/analytics-worker
./deploy-ec2.sh
```

#### Option 3: AWS Systems Manager

```bash
# Run command on Auto Scaling Group instances
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --targets "Key=tag:Name,Values=analytics-worker" \
  --parameters 'commands=["cd /home/ec2-user/analytics-worker && git pull && ./deploy-ec2.sh"]'
```

## Stress Scenario: Query Storm

**Story:** End of quarter. Finance team runs 500 concurrent Redshift queries for revenue reports. Analytics Worker processes each query result with extensive data transformation.

**CPU-Intensive Operations:**
- Complex Redshift analytical queries (90-day aggregations)
- Large result set processing (100K+ rows)
- JSON serialization/deserialization
- Hash operations (SHA256, MD5) for data integrity
- Floating point calculations for metrics
- Multi-threaded query execution

**Expected Impact:**
- EC2 CPU → 90%
- Redshift CPU → 90%+
- Redshift concurrent query count spikes
- Query queue time increases
- Network throughput increases (result set transfer)
- CloudWatch metrics spike

**Duration:** 10 minutes (default)

### Trigger Stress Scenario

```bash
# SSH to EC2 instance
ssh -i your-key.pem ec2-user@<ec2-ip>

# Run stress scenario
cd /opt/cloudcafe/analytics-worker
python3.11 worker.py stress 600 90

# Arguments:
# - Duration: 600 seconds (10 minutes)
# - Target CPU: 90%

# Monitor CPU in another terminal
watch -n 5 'top -bn1 | grep "Cpu(s)"'
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `KINESIS_STREAM_NAME` | Kinesis stream name | `order-events` |
| `REDSHIFT_CLUSTER_ID` | Redshift cluster ID | `cloudcafe-redshift-dev` |
| `REDSHIFT_DATABASE` | Redshift database | `analytics` |
| `REDSHIFT_DB_USER` | Redshift username | `admin` |
| `AWS_REGION` | AWS region | `us-east-1` |
| `ENVIRONMENT` | Environment name | `dev` |
| `BATCH_SIZE` | Records per batch | `100` |
| `POLL_INTERVAL` | Seconds between polls | `5` |

## Redshift Schema

The worker writes to the following table:

```sql
CREATE TABLE fact_orders (
    order_id VARCHAR(100) PRIMARY KEY,
    customer_id VARCHAR(100) NOT NULL,
    store_id INTEGER NOT NULL,
    total_amount DECIMAL(10, 2) NOT NULL,
    item_count INTEGER NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    event_timestamp TIMESTAMP NOT NULL
);

CREATE INDEX idx_customer_id ON fact_orders(customer_id);
CREATE INDEX idx_store_id ON fact_orders(store_id);
CREATE INDEX idx_event_timestamp ON fact_orders(event_timestamp);
CREATE INDEX idx_event_type ON fact_orders(event_type);
```

## Monitoring

### CloudWatch Metrics

Custom metrics in `CloudCafe/Analytics` namespace:

- `RecordsProcessed` - Number of Kinesis records processed
- `RedshiftEventsWritten` - Events written to Redshift
- `RedshiftWriteDuration` - Time to write batch (ms)
- `ShardProcessingError` / `RedshiftWriteError` / `WorkerError` - Error counts
- `QueryStormCPU` - CPU usage during stress scenario
- `QueryStormIterations` - Stress scenario progress
- `QueryStormCompleted` - Stress scenario completion

### View Metrics

```bash
# View records processed
aws cloudwatch get-metric-statistics \
  --namespace CloudCafe/Analytics \
  --metric-name RecordsProcessed \
  --start-time $(date -u -d "1 hour ago" +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum \
  --dimensions Name=Environment,Value=dev

# View Redshift write latency
aws cloudwatch get-metric-statistics \
  --namespace CloudCafe/Analytics \
  --metric-name RedshiftWriteDuration \
  --start-time $(date -u -d "1 hour ago" +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average,Maximum
```

### Application Logs

```bash
# View service logs
sudo journalctl -u analytics-worker -f

# View last 100 lines
sudo journalctl -u analytics-worker -n 100

# View CloudWatch Logs
aws logs tail /cloudcafe/analytics-worker --follow
```

## Performance Testing

### Generate Test Events

```bash
# Use Order Service to generate events
for i in {1..1000}; do
  curl -X POST http://<order-service-url>/orders \
    -H "Content-Type: application/json" \
    -d '{
      "store_id": 1,
      "customer_id": "test-'$i'",
      "items": [{"item_id": "latte", "quantity": 1}],
      "total_amount": 4.95
    }'
done

# Check worker processing
sudo journalctl -u analytics-worker -f
```

### Monitor Processing Rate

```bash
# Watch CloudWatch metrics
watch -n 10 'aws cloudwatch get-metric-statistics \
  --namespace CloudCafe/Analytics \
  --metric-name RecordsProcessed \
  --start-time $(date -u -d "5 minutes ago" +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Sum \
  --query "Datapoints[*].Sum" \
  --output text'
```

### Query Redshift

```bash
# Connect to Redshift
psql -h <redshift-endpoint> -U admin -d analytics

# Check record count
SELECT COUNT(*) FROM fact_orders;

# Top stores by revenue
SELECT
    store_id,
    COUNT(*) as order_count,
    SUM(total_amount) as total_revenue,
    AVG(total_amount) as avg_order_value
FROM fact_orders
GROUP BY store_id
ORDER BY total_revenue DESC
LIMIT 10;

# Orders over time
SELECT
    DATE_TRUNC('hour', event_timestamp) as hour,
    COUNT(*) as orders,
    SUM(total_amount) as revenue
FROM fact_orders
WHERE event_timestamp > CURRENT_DATE - INTERVAL '24 hours'
GROUP BY hour
ORDER BY hour DESC;
```

## Troubleshooting

### Worker Not Processing Records

**Symptoms:**
- Service running but no logs
- RecordsProcessed metric = 0

**Solutions:**
```bash
# Check Kinesis stream exists
aws kinesis describe-stream --stream-name order-events

# Check shard iterator
aws kinesis get-shard-iterator \
  --stream-name order-events \
  --shard-id shardId-000000000000 \
  --shard-iterator-type LATEST

# Verify IAM permissions
# Worker needs: kinesis:DescribeStream, kinesis:GetRecords, kinesis:GetShardIterator

# Check if records are being published
aws kinesis get-records \
  --shard-iterator <iterator-from-above>
```

### Redshift Write Errors

**Symptoms:**
- "RedshiftWriteError" metric increasing
- Worker logs show SQL errors

**Solutions:**
```bash
# Check Redshift cluster status
aws redshift describe-clusters \
  --cluster-identifier cloudcafe-redshift-dev

# Verify table exists
psql -h <endpoint> -U admin -d analytics \
  -c "SELECT * FROM fact_orders LIMIT 1;"

# Check IAM permissions
# Worker needs: redshift-data:ExecuteStatement

# View query failures
SELECT query, error
FROM stl_error
ORDER BY starttime DESC
LIMIT 10;
```

### High CPU Usage (Non-Stress)

**Symptoms:**
- CPU > 70% during normal operation
- Worker lagging behind stream

**Solutions:**
```bash
# Increase POLL_INTERVAL (less aggressive polling)
export POLL_INTERVAL=10

# Reduce BATCH_SIZE (smaller batches)
export BATCH_SIZE=50

# Scale horizontally (add more EC2 instances)
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name analytics-worker-asg \
  --desired-capacity 3

# Or scale up instance type
# t3.large → t3.xlarge (4 vCPU, 16 GB)
```

### Kinesis Iterator Expired

**Symptoms:**
- "ExpiredIteratorException" in logs
- Worker stops processing

**Solutions:**
```bash
# Worker will automatically reinitialize
# Or restart worker
sudo systemctl restart analytics-worker

# Check shard lag
aws kinesis describe-stream-summary \
  --stream-name order-events \
  --query 'StreamDescriptionSummary.OpenShardCount'
```

## Best Practices

### Scaling

1. **Horizontal Scaling:** Add more EC2 instances to process different shards
2. **Batch Size Tuning:** Increase `BATCH_SIZE` for higher throughput
3. **Poll Interval:** Decrease for lower latency, increase to reduce costs
4. **Auto Scaling:** Use CloudWatch alarms on CPU or lag metrics

### Error Handling

- Worker automatically retries failed Kinesis reads
- Redshift write failures are logged but don't stop processing
- Dead letter queue (DLQ) for persistent failures (TODO)

### Cost Optimization

```bash
# Use Spot Instances for EC2 (60-90% savings)
# Pause Redshift cluster when not in use
aws redshift pause-cluster --cluster-identifier cloudcafe-redshift-dev

# Resume when needed
aws redshift resume-cluster --cluster-identifier cloudcafe-redshift-dev

# Use Kinesis Data Firehose alternative (managed)
# - No EC2 instances to manage
# - Auto-scales
# - Direct S3/Redshift integration
```

## Architecture Decisions

### Why EC2 instead of Lambda?

- **Persistent connections:** Kinesis requires long-lived shard iterators
- **Processing time:** Complex queries can exceed Lambda 15-min timeout
- **Cost:** For continuous processing, EC2 is more cost-effective
- **Control:** Full control over polling, batching, error handling

### Why Redshift Data API?

- **No connection pooling:** Serverless API, no connection limits
- **Asynchronous:** Fire-and-forget for better throughput
- **Managed:** AWS handles query execution and retries
- **Secure:** IAM-based auth, no password management

## Related Services

- **Order Service:** Publishes order events to Kinesis
- **Inventory Service:** Publishes inventory events to Kinesis
- **Payment Processor:** Publishes payment events to Kinesis
- **Redshift:** Data warehouse for all analytics

## License

MIT License
