# Payment Processor (Lambda)

Serverless payment processing function triggered by SQS FIFO queue. Processes credit card transactions, performs fraud detection, and logs to DynamoDB.

## Technology Stack

- **Runtime:** Python 3.11
- **Trigger:** SQS FIFO Queue
- **Database:** DynamoDB (transaction log)
- **Deployment:** AWS Lambda

## Features

- Asynchronous payment processing from SQS
- Fraud detection with CPU-intensive scoring
- Transaction logging to DynamoDB
- Cold start stress scenario (Black Friday simulation)
- CloudWatch custom metrics
- FIFO queue for ordered processing

## Stress Scenario: Cold Start Avalanche

**Story:** Black Friday at midnight. 10,000 concurrent customers complete checkout simultaneously. Lambda auto-scales from 0 to 10,000 concurrent executions. Every invocation experiences a cold start.

**CPU-Intensive Operations:**
- 3-second initialization delay (loading payment SDKs)
- 10M SHA256 hash operations during cold start
- Fraud scoring with 10K iterations per payment
- Pattern matching and validation

**Expected Impact:**
- Lambda duration → 3000ms+ (p99)
- Cold start percentage → 100%
- Concurrent executions → 10,000
- SQS message age increases
- CloudWatch shows duration spike

**Duration:** Gradual ramp-up over 5-10 minutes

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `AWS_REGION` | AWS region | `us-east-1` |
| `DYNAMODB_TABLE` | Transaction table name | `cloudcafe-payment-transactions-dev` |
| `ENVIRONMENT` | Environment name | `dev` |
| `STRESS_MODE` | Enable stress mode | `none` |

## SQS Message Format

```json
{
  "payment_id": "pay-abc123",
  "order_id": "ord-123",
  "customer_id": "cust-456",
  "amount": 25.99,
  "payment_method": "credit_card",
  "billing_address": {
    "street": "123 Main St",
    "city": "Seattle",
    "state": "WA",
    "zip": "98101"
  }
}
```

## Lambda Response

```json
{
  "statusCode": 200,
  "body": {
    "processed": 10,
    "failed": 0,
    "cold_start": true,
    "duration_ms": 3245.67
  }
}
```

## DynamoDB Transaction Schema

```json
{
  "transaction_id": "txn-pay-abc123",
  "payment_id": "pay-abc123",
  "order_id": "ord-123",
  "customer_id": "cust-456",
  "amount": 25.99,
  "payment_method": "credit_card",
  "fraud_score": 15,
  "status": "completed",
  "gateway_response": {
    "status": "approved",
    "authorization_code": "AUTH123ABC",
    "timestamp": "2024-01-01T12:00:00Z"
  },
  "processed_at": "2024-01-01T12:00:00Z"
}
```

## Deployment

### Create Deployment Package

```bash
cd services/payment-processor

# Install dependencies
pip install -r requirements.txt -t package/

# Copy handler
cp handler.py package/

# Create ZIP
cd package
zip -r ../payment-processor.zip .
cd ..
```

### Deploy with AWS CLI

```bash
# Create/update Lambda function
aws lambda update-function-code \
  --function-name cloudcafe-payment-processor-dev \
  --zip-file fileb://payment-processor.zip

# Update environment variables
aws lambda update-function-configuration \
  --function-name cloudcafe-payment-processor-dev \
  --environment Variables="{
    DYNAMODB_TABLE=cloudcafe-payment-transactions-dev,
    ENVIRONMENT=dev,
    AWS_REGION=us-east-1
  }"

# Enable stress mode
aws lambda update-function-configuration \
  --function-name cloudcafe-payment-processor-dev \
  --environment Variables="{
    STRESS_MODE=cold_start,
    DYNAMODB_TABLE=cloudcafe-payment-transactions-dev
  }"
```

### Test Locally

```bash
# Run handler locally
python handler.py

# Or with Python
python3 -c "
import handler
import json

event = {
    'Records': [{
        'body': json.dumps({
            'payment_id': 'test-123',
            'order_id': 'ord-123',
            'customer_id': 'cust-456',
            'amount': 25.99,
            'payment_method': 'credit_card'
        })
    }]
}

result = handler.lambda_handler(event, {})
print(json.dumps(result, indent=2))
"
```

## Trigger Cold Start Stress

```bash
# Send 1000 messages to SQS to trigger Lambda scaling
for i in {1..1000}; do
  aws sqs send-message \
    --queue-url https://sqs.us-east-1.amazonaws.com/ACCOUNT/cloudcafe-payment-processing-dev.fifo \
    --message-body "{\"payment_id\":\"pay-$i\",\"order_id\":\"ord-$i\",\"customer_id\":\"cust-$i\",\"amount\":$((RANDOM % 100 + 10)).99,\"payment_method\":\"credit_card\"}" \
    --message-group-id "payment-group-$((i % 10))" &
done

wait

echo "✅ Sent 1000 payment messages"
echo "📊 Check Lambda metrics in CloudWatch"
```

## Monitoring

### CloudWatch Metrics

Custom metrics in `CloudCafe/Lambda` namespace:

- `ProcessedPayments` - Successfully processed payments
- `FailedPayments` - Failed payment processing
- `Duration` - Processing duration (ms)
- `ColdStart` - Cold start occurrences
- `LambdaErrors` - Lambda invocation errors

### AWS Lambda Metrics

```bash
# View concurrent executions
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name ConcurrentExecutions \
  --dimensions Name=FunctionName,Value=cloudcafe-payment-processor-dev \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T01:00:00Z \
  --period 60 \
  --statistics Maximum

# View duration (p99)
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Duration \
  --dimensions Name=FunctionName,Value=cloudcafe-payment-processor-dev \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T01:00:00Z \
  --period 60 \
  --statistics Average \
  --extended-statistics p99

# View errors
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Errors \
  --dimensions Name=FunctionName,Value=cloudcafe-payment-processor-dev \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T01:00:00Z \
  --period 60 \
  --statistics Sum
```

## Performance Tuning

### Memory Allocation

```bash
# Test different memory sizes
for MEMORY in 128 256 512 1024; do
  echo "Testing with ${MEMORY}MB memory..."

  aws lambda update-function-configuration \
    --function-name cloudcafe-payment-processor-dev \
    --memory-size $MEMORY

  # Wait for update
  sleep 10

  # Run test
  # ... measure performance ...
done
```

### Provisioned Concurrency

```bash
# Enable provisioned concurrency to reduce cold starts
aws lambda put-provisioned-concurrency-config \
  --function-name cloudcafe-payment-processor-dev \
  --provisioned-concurrent-executions 10
```

## Troubleshooting

### High Cold Start Rate

**Symptoms:**
- Duration > 3000ms consistently
- ColdStart metric = 1 for most invocations

**Solutions:**
1. Enable provisioned concurrency
2. Increase memory allocation (faster CPU)
3. Optimize initialization code
4. Use Lambda SnapStart (Java only)

### DynamoDB Write Errors

**Symptoms:**
- FailedPayments metric increasing
- "ProvisionedThroughputExceededException" in logs

**Solutions:**
```bash
# Enable DynamoDB auto-scaling
aws application-autoscaling register-scalable-target \
  --service-namespace dynamodb \
  --resource-id table/cloudcafe-payment-transactions-dev \
  --scalable-dimension dynamodb:table:WriteCapacityUnits \
  --min-capacity 5 \
  --max-capacity 100

# Or switch to on-demand billing
aws dynamodb update-table \
  --table-name cloudcafe-payment-transactions-dev \
  --billing-mode PAY_PER_REQUEST
```

### SQS Message Age Increasing

**Symptoms:**
- Messages not processed quickly enough
- ApproximateAgeOfOldestMessage > 300 seconds

**Solutions:**
1. Increase Lambda reserved concurrency
2. Increase SQS batch size (max 10)
3. Reduce Lambda duration
4. Add more Lambda functions (parallel processing)

## Architecture

```
┌─────────────┐
│ Order Service│
└──────┬──────┘
       │ Publish
       ▼
┌─────────────────────┐
│ SQS FIFO Queue      │
│ payment-processing  │
└──────┬──────────────┘
       │ Trigger (batch: 10)
       ▼
┌─────────────────────┐
│ Lambda Function     │
│ Payment Processor   │
│ - Validate          │
│ - Fraud check       │
│ - Process           │
└──────┬──────────────┘
       │ Write
       ▼
┌─────────────────────┐
│ DynamoDB Table      │
│ payment-transactions│
└─────────────────────┘
```

## Cost Optimization

**Lambda Pricing:**
- $0.20 per 1M requests
- $0.0000166667 per GB-second

**Example:**
- 1M payments/month
- 512 MB memory
- 3s average duration (with cold starts)

**Cost Calculation:**
```
Requests: $0.20
Compute: 1M × 3s × 0.5GB × $0.0000166667 = $25
Total: ~$25/month
```

**Optimization:**
- Reduce cold starts with provisioned concurrency
- Optimize fraud detection algorithm
- Use smaller memory if possible

## License

MIT License
