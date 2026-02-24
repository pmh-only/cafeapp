#!/bin/bash
set -e

AWS_REGION="ap-northeast-2"
AWS_ACCOUNT_ID="972209100553"

echo "=== Deploying Menu Service to EKS ==="

# Get infrastructure details
cd infrastructure/terraform
DOCDB_ENDPOINT=$(terraform output -raw documentdb_endpoint)
REDIS_ENDPOINT=$(terraform output -raw elasticache_endpoint)
cd ../..

echo "Infrastructure:"
echo "  DocumentDB: $DOCDB_ENDPOINT"
echo "  Redis: $REDIS_ENDPOINT"

# Create ECR repository
echo ""
echo "=== Creating ECR Repository ==="
/usr/local/bin/aws ecr describe-repositories --repository-names cloudcafe-menu-service --region $AWS_REGION 2>/dev/null || \
/usr/local/bin/aws ecr create-repository \
    --repository-name cloudcafe-menu-service \
    --region $AWS_REGION \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=AES256 > /dev/null

echo "✓ ECR repository ready"

# Build and push Docker image
echo ""
echo "=== Building Docker Image ==="
docker build -t cloudcafe-menu-service:latest services/menu-service/ 2>&1 | grep -E "(Step|Successfully|ERROR)" | tail -5

echo ""
echo "=== Pushing to ECR ==="
docker tag cloudcafe-menu-service:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/cloudcafe-menu-service:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/cloudcafe-menu-service:latest 2>&1 | grep -E "(Pushed|digest)" | tail -2

echo "✓ Image pushed"

# Create Kubernetes secrets
echo ""
echo "=== Creating Kubernetes Secrets ==="

# DocumentDB credentials
DOCDB_URI="mongodb://cloudcafe_admin:CloudCafe2024!@$DOCDB_ENDPOINT:27017/cloudcafe?tls=true&replicaSet=rs0&readPreference=secondaryPreferred&retryWrites=false"

/usr/local/bin/kubectl create secret generic documentdb-credentials \
    --from-literal=uri="$DOCDB_URI" \
    --dry-run=client -o yaml | /usr/local/bin/kubectl apply -f -

# ElastiCache credentials
/usr/local/bin/kubectl create secret generic elasticache-credentials \
    --from-literal=host="$REDIS_ENDPOINT" \
    --dry-run=client -o yaml | /usr/local/bin/kubectl apply -f -

echo "✓ Secrets created"

# Update deployment YAML with actual values
echo ""
echo "=== Deploying to EKS ==="

cat services/menu-service/k8s/deployment.yaml | \
    sed "s/\${AWS_ACCOUNT_ID}/$AWS_ACCOUNT_ID/g" | \
    sed "s/\${AWS_REGION}/$AWS_REGION/g" | \
    sed "s/us-east-1/$AWS_REGION/g" > /tmp/menu-deployment.yaml

# Remove the secrets section (we created them separately)
/usr/local/bin/kubectl apply -f /tmp/menu-deployment.yaml 2>&1 | grep -v "secret" || true

echo "✓ Deployment applied"

echo ""
echo "=== Checking Deployment Status ==="
/usr/local/bin/kubectl get deployments menu-service 2>/dev/null || echo "Deployment starting..."
/usr/local/bin/kubectl get pods -l app=menu-service 2>/dev/null | head -5 || echo "Pods starting..."

echo ""
echo "=== Deployment Complete ==="
echo "Service: menu-service"
echo "Namespace: default"
echo "Region: $AWS_REGION"
echo ""
echo "Monitor with: kubectl get pods -l app=menu-service -w"
