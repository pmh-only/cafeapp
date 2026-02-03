# Menu Service (Node.js/Express)

Menu catalog management service built with Node.js and Express, deployed on Amazon EKS.

## Technology Stack

- **Runtime:** Node.js 20
- **Framework:** Express.js
- **Database:** DocumentDB (MongoDB-compatible)
- **Cache:** ElastiCache (Redis)
- **Deployment:** Amazon EKS (Kubernetes)

## Features

- Menu catalog with flexible schema
- Redis caching for fast lookups (5-minute TTL)
- DocumentDB for persistent storage
- Built-in CPU stress scenario (Menu Sync Storm)
- CloudWatch custom metrics
- Auto-scaling based on CPU/memory

## API Endpoints

### Health Check
```
GET /health
```

Response:
```json
{
  "status": "healthy",
  "service": "menu-service",
  "timestamp": "2024-01-01T12:00:00Z",
  "connections": {
    "mongodb": true,
    "redis": true
  }
}
```

### Get All Menu Items
```
GET /menu/items?category=Coffee
```

Response:
```json
{
  "items": [
    {
      "item_id": "latte-001",
      "name": "Caffe Latte",
      "description": "Classic espresso with steamed milk",
      "category": "Coffee",
      "price": 4.95,
      "calories": 190,
      "ingredients": ["espresso", "milk", "foam"],
      "allergens": ["milk"],
      "available": true,
      "image_url": "https://..."
    }
  ],
  "cached": true,
  "count": 15,
  "duration_ms": 12
}
```

### Get Single Item
```
GET /menu/items/:itemId
```

### Create/Update Item
```
POST /menu/items
Content-Type: application/json

{
  "item_id": "latte-001",
  "name": "Caffe Latte",
  "category": "Coffee",
  "price": 4.95,
  "calories": 190
}
```

### Trigger Stress Scenario
```
POST /stress/menu-sync
Content-Type: application/json

{
  "duration_seconds": 180,
  "target_cpu": 70
}
```

## Stress Scenario: Menu Sync Storm

**Story:** Marketing department launches seasonal menu update (Pumpkin Spice season!). All 50 Kubernetes pods receive webhook notification to sync 10,000 menu items from upstream API.

**CPU-Intensive Operations:**
- JSON parsing/stringifying (100x per item)
- SHA256 image hash validation
- Nutritional calculations (floating point)
- Description text processing
- Base64 encoding/decoding

**Expected Impact:**
- Node.js CPU → 70%
- DocumentDB CPU spike
- ElastiCache cache evictions
- Network throughput increases
- Pod memory usage increases

**Duration:** 3 minutes (default)

## Build & Deploy

### Local Development

```bash
# Install dependencies
npm install

# Set environment variables
export MONGODB_URI="mongodb://localhost:27017/cloudcafe"
export REDIS_HOST="localhost"
export REDIS_PORT="6379"
export AWS_REGION="us-east-1"

# Run locally
npm start

# Or with auto-reload
npm run dev

# Test
curl http://localhost:8080/health
```

### Build Docker Image

```bash
# Build
docker build -t menu-service .

# Run
docker run -p 8080:8080 \
  -e MONGODB_URI="mongodb://..." \
  -e REDIS_HOST="localhost" \
  menu-service
```

### Deploy to EKS

```bash
# Set environment variables
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION=us-east-1

# Build and push to ECR
aws ecr create-repository --repository-name cloudcafe-menu-service --region $AWS_REGION
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

docker build -t cloudcafe-menu-service .
docker tag cloudcafe-menu-service:latest \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/cloudcafe-menu-service:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/cloudcafe-menu-service:latest

# Update kubeconfig
aws eks update-kubeconfig --name cloudcafe-eks-dev --region $AWS_REGION

# Update secrets with real credentials
kubectl create secret generic documentdb-credentials \
  --from-literal=uri="mongodb://username:password@docdb-endpoint:27017/cloudcafe"

kubectl create secret generic elasticache-credentials \
  --from-literal=host="elasticache-endpoint.cache.amazonaws.com"

# Deploy to Kubernetes
envsubst < k8s/deployment.yaml | kubectl apply -f -

# Check status
kubectl get pods -l app=menu-service
kubectl get svc menu-service
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PORT` | HTTP server port | `8080` |
| `MONGODB_URI` | DocumentDB connection string | - |
| `REDIS_HOST` | ElastiCache endpoint | `localhost` |
| `REDIS_PORT` | Redis port | `6379` |
| `AWS_REGION` | AWS region | `us-east-1` |
| `ENVIRONMENT` | Environment name | `dev` |

## Monitoring

### CloudWatch Metrics

Custom metrics in `CloudCafe/Menu` namespace:

- `CacheHit` / `CacheMiss` - Cache performance
- `QueryDuration` - Database query duration
- `QueryError` / `UpdateError` - Error counts
- `MenuItemUpdated` - Update operations
- `MenuSyncCPU` - CPU during sync scenario
- `MenuSyncIterations` - Sync iterations
- `MenuSyncCompleted` - Sync completion events

### Kubernetes Metrics

```bash
# View pod metrics
kubectl top pods -l app=menu-service

# View HPA status
kubectl get hpa menu-service-hpa

# View logs
kubectl logs -l app=menu-service --tail=100 -f

# Check service endpoints
kubectl get endpoints menu-service
```

## Performance Testing

```bash
# Load test
k6 run load-testing/k6/scenarios/menu-load.js

# Trigger sync storm
curl -X POST http://<service-url>/stress/menu-sync \
  -H "Content-Type: application/json" \
  -d '{"duration_seconds": 180, "target_cpu": 70}'

# Watch resource usage
kubectl top pods -l app=menu-service --watch
```

## Caching Strategy

**Cache Keys:**
- `menu:all` - All available items (5min TTL)
- `menu:category:{category}` - Items by category (5min TTL)
- `menu:item:{item_id}` - Single item (10min TTL)

**Cache Invalidation:**
- On item create/update: Invalidate relevant keys
- On sync: Flush all menu keys

**Cache Hit Rate Target:** 80%+

## Troubleshooting

### High Memory Usage

**Symptoms:**
- Pod OOMKilled
- Memory usage > 900MB

**Solutions:**
1. Increase memory limits in deployment.yaml
2. Optimize image data handling
3. Implement streaming for large responses

### DocumentDB Connection Issues

**Symptoms:**
- "MongoNetworkError" in logs
- Health check fails for MongoDB

**Solutions:**
```bash
# Verify security group
aws docdb describe-db-clusters \
  --db-cluster-identifier cloudcafe-docdb-dev \
  --query 'DBClusters[0].VpcSecurityGroups'

# Test connectivity from pod
kubectl exec -it <pod-name> -- wget -O- docdb-endpoint:27017

# Check secret
kubectl get secret documentdb-credentials -o yaml
```

### Cache Miss Storm

**Symptoms:**
- Cache hit rate < 50%
- DocumentDB CPU spike
- Slow response times

**Solutions:**
1. Increase Redis memory
2. Adjust TTL values
3. Implement cache warming on startup
4. Add cache preloading for popular items

## Architecture

```
┌─────────────┐
│   ALB/NLB   │
└──────┬──────┘
       │
┌──────▼──────────────────┐
│   EKS Cluster (K8s)     │
│                          │
│  ┌────────────────────┐ │
│  │  Menu Service Pods │ │
│  │  (3-10 replicas)   │ │
│  │  - Node.js 20      │ │
│  │  - Express.js      │ │
│  └───┬─────────┬──────┘ │
└──────┼─────────┼────────┘
       │         │
   ┌───▼────┐ ┌─▼────────┐
   │Document│ │ElastiCache│
   │  DB    │ │  (Redis) │
   │(MongoDB)│ │ (Cache)  │
   └────────┘ └──────────┘
```

## License

MIT License
