#!/bin/bash
set -e

AWS_REGION="ap-northeast-2"
AWS_ACCOUNT_ID="972209100553"

echo "=== Deploying Inventory Service to EKS ==="

# Get infrastructure details
cd infrastructure/terraform
MEMORYDB_ENDPOINT=$(terraform output -raw memorydb_cluster_endpoint)
DYNAMODB_TABLE=$(terraform output -json dynamodb_table_names | jq -r '.store_inventory')
cd ../..

echo "Infrastructure:"
echo "  MemoryDB: $MEMORYDB_ENDPOINT"
echo "  DynamoDB: $DYNAMODB_TABLE"

# Create ECR repository
echo ""
echo "=== Creating ECR Repository ==="
/usr/local/bin/aws ecr describe-repositories --repository-names cloudcafe-inventory-service --region $AWS_REGION 2>/dev/null || \
/usr/local/bin/aws ecr create-repository \
    --repository-name cloudcafe-inventory-service \
    --region $AWS_REGION \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=AES256 > /dev/null

echo "✓ ECR repository ready"

# Build and push Docker image
echo ""
echo "=== Building Docker Image ==="
docker build -t cloudcafe-inventory-service:latest services/inventory-service/ 2>&1 | grep -E "(Step|Successfully|ERROR|#[0-9]+ DONE)" | tail -10

echo ""
echo "=== Pushing to ECR ==="
docker tag cloudcafe-inventory-service:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/cloudcafe-inventory-service:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/cloudcafe-inventory-service:latest 2>&1 | grep -E "(Pushed|digest)" | tail -2

echo "✓ Image pushed"

# Create Kubernetes secrets
echo ""
echo "=== Creating Kubernetes Secrets ==="

/usr/local/bin/kubectl create secret generic memorydb-credentials \
    --from-literal=endpoint="$MEMORYDB_ENDPOINT" \
    --dry-run=client -o yaml | /usr/local/bin/kubectl apply -f -

echo "✓ Secrets created"

# Update deployment YAML with actual values
echo ""
echo "=== Deploying to EKS ==="

cat services/inventory-service/k8s/deployment.yaml | \
    sed "s/\${AWS_ACCOUNT_ID}/$AWS_ACCOUNT_ID/g" | \
    sed "s/\${AWS_REGION}/$AWS_REGION/g" | \
    sed "s/us-east-1/$AWS_REGION/g" | \
    sed "s/cloudcafe-store-inventory-dev/$DYNAMODB_TABLE/g" > /tmp/inventory-deployment.yaml

/usr/local/bin/kubectl apply -f /tmp/inventory-deployment.yaml

echo "✓ Deployment applied"

echo ""
echo "=== Checking Deployment Status ==="
/usr/local/bin/kubectl get deployments inventory-service 2>/dev/null || echo "Deployment starting..."
/usr/local/bin/kubectl get pods -l app=inventory-service 2>/dev/null | head -5 || echo "Pods starting..."

echo ""
echo "=== Deployment Complete ==="
echo "Service: inventory-service"
echo "Namespace: default"
echo "Region: $AWS_REGION"
echo ""
echo "Monitor with: kubectl get pods -l app=inventory-service -w"
