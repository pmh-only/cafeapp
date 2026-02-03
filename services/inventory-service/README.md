# Inventory Service (Go)

Real-time store inventory management service built with Go, deployed on Amazon EKS.

## Technology Stack

- **Language:** Go 1.21
- **Web Framework:** Gorilla Mux
- **AWS SDK:** aws-sdk-go-v2
- **Database:** DynamoDB (primary), MemoryDB (atomic counters)
- **Deployment:** Amazon EKS (Kubernetes)

## Features

- Real-time inventory tracking for 30,000 stores
- DynamoDB for persistent storage
- MemoryDB for atomic inventory counters
- Redis caching for fast lookups
- Built-in CPU stress scenario (Restock Storm)
- CloudWatch custom metrics

## API Endpoints

### Health Check
```
GET /health
```

Response:
```json
{
  "status": "healthy",
  "service": "inventory-service",
  "timestamp": "2024-01-01T12:00:00Z"
}
```

### Get Store Inventory
```
GET /inventory/store/{storeId}
```

Response:
```json
[
  {
    "store_id": "store-1",
    "sku": "SKU-1001",
    "quantity": 150,
    "updated_at": "2024-01-01T12:00:00Z"
  }
]
```

### Update Inventory
```
POST /inventory/update
Content-Type: application/json

{
  "store_id": "store-1",
  "sku": "SKU-1001",
  "quantity": 150
}
```

### Trigger Stress Scenario
```
POST /stress/restock
Content-Type: application/json

{
  "duration_seconds": 180,
  "target_cpu": 80
}
```

## Stress Scenario: Restock Storm

**Story:** Every Sunday at 3 AM, all 30,000 stores simultaneously sync their inventory with the central warehouse system. Each store updates 5000+ SKUs.

**CPU-Intensive Operations:**
- SHA256 hash calculations for data integrity
- JSON marshaling/unmarshaling
- Fibonacci calculations for validation
- Concurrent goroutines per store

**Expected Impact:**
- EKS pod CPU → 80%
- DynamoDB write capacity consumed
- MemoryDB atomic counter updates
- Pod restart count may increase

**Duration:** 3 minutes (default)

## Build & Deploy

### Local Development

```bash
# Install dependencies
go mod download

# Run locally
go run cmd/main.go

# Test
curl http://localhost:8080/health
```

### Build Docker Image

```bash
# Build
docker build -t inventory-service .

# Run
docker run -p 8080:8080 \
  -e AWS_REGION=us-east-1 \
  -e DYNAMODB_TABLE=cloudcafe-store-inventory-dev \
  inventory-service
```

### Deploy to EKS

```bash
# Set environment variables
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION=us-east-1

# Build and push to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

docker build -t cloudcafe-inventory-service .
docker tag cloudcafe-inventory-service:latest \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/cloudcafe-inventory-service:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/cloudcafe-inventory-service:latest

# Update kubeconfig
aws eks update-kubeconfig --name cloudcafe-eks-dev --region $AWS_REGION

# Deploy to Kubernetes
envsubst < k8s/deployment.yaml | kubectl apply -f -

# Check status
kubectl get pods -l app=inventory-service
kubectl get svc inventory-service
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PORT` | HTTP server port | `8080` |
| `AWS_REGION` | AWS region | `us-east-1` |
| `DYNAMODB_TABLE` | DynamoDB table name | `cloudcafe-store-inventory-dev` |
| `MEMORYDB_ENDPOINT` | MemoryDB endpoint | - |

## Monitoring

### CloudWatch Metrics

Custom metrics emitted to `CloudCafe/Inventory` namespace:

- `RestockCPU` - CPU utilization during restock
- `RestockIterations` - Number of processing iterations
- `RestockCompleted` - Restock scenario completion
- `QueryDuration` - Inventory query duration
- `CacheHit` / `CacheMiss` - Cache performance
- `InventoryUpdated` - Inventory update count
- `QueryError` / `UpdateError` - Error counts

### Kubernetes Metrics

```bash
# View pod metrics
kubectl top pods -l app=inventory-service

# View HPA status
kubectl get hpa inventory-service-hpa

# View logs
kubectl logs -l app=inventory-service --tail=100 -f
```

## Performance Testing

```bash
# Load test with K6
k6 run load-testing/k6/scenarios/inventory-stress.js

# Trigger restock storm
curl -X POST http://<service-url>/stress/restock \
  -H "Content-Type: application/json" \
  -d '{"duration_seconds": 180, "target_cpu": 80}'

# Watch metrics in CloudWatch
aws cloudwatch get-metric-statistics \
  --namespace CloudCafe/Inventory \
  --metric-name RestockCPU \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T01:00:00Z \
  --period 60 \
  --statistics Average
```

## Troubleshooting

### Pod Not Starting

```bash
# Check pod events
kubectl describe pod <pod-name>

# Check logs
kubectl logs <pod-name>

# Verify IAM role
kubectl describe sa inventory-service
```

### High Memory Usage

- Check DynamoDB query sizes
- Verify Redis connection pooling
- Review memory limits in deployment.yaml

### DynamoDB Throttling

```bash
# Check table metrics
aws dynamodb describe-table --table-name cloudcafe-store-inventory-dev

# Enable auto-scaling
aws application-autoscaling register-scalable-target \
  --service-namespace dynamodb \
  --resource-id table/cloudcafe-store-inventory-dev \
  --scalable-dimension dynamodb:table:WriteCapacityUnits \
  --min-capacity 5 \
  --max-capacity 100
```

## Architecture

```
┌─────────────┐
│   ALB/NLB   │
└──────┬──────┘
       │
┌──────▼──────────────────────┐
│   EKS Cluster (Kubernetes)  │
│                              │
│  ┌────────────────────────┐ │
│  │ Inventory Service Pods │ │
│  │  (3-10 replicas)       │ │
│  │  - Go 1.21             │ │
│  │  - Gorilla Mux         │ │
│  │  - AWS SDK v2          │ │
│  └───┬─────────────────┬──┘ │
└──────┼─────────────────┼────┘
       │                 │
   ┌───▼────┐      ┌────▼─────┐
   │DynamoDB│      │ MemoryDB │
   │(NoSQL) │      │ (Redis)  │
   └────────┘      └──────────┘
```

## Contributing

This service follows Go best practices:
- Error handling with explicit returns
- Context propagation for cancellation
- Structured logging
- Graceful shutdown
- Resource cleanup

## License

MIT License
