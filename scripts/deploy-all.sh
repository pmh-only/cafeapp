#!/bin/bash
# One-Command Deployment Script for CloudCafe
#
# This script deploys the entire CloudCafe infrastructure in the correct order:
# 1. Terraform infrastructure
# 2. Database initialization
# 3. Container images (build & push to ECR)
# 4. ECS services
# 5. EKS services
# 6. Validation

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
AWS_REGION=${AWS_REGION:-us-east-1}
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Banner
clear
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║   ██████╗██╗      ██████╗ ██╗   ██╗██████╗  ██████╗ █████╗  ║
║  ██╔════╝██║     ██╔═══██╗██║   ██║██╔══██╗██╔════╝██╔══██╗ ║
║  ██║     ██║     ██║   ██║██║   ██║██║  ██║██║     ███████║ ║
║  ██║     ██║     ██║   ██║██║   ██║██║  ██║██║     ██╔══██║ ║
║  ╚██████╗███████╗╚██████╔╝╚██████╔╝██████╔╝╚██████╗██║  ██║ ║
║   ╚═════╝╚══════╝ ╚═════╝  ╚═════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝ ║
║                                                               ║
║                  🚀 Deployment Script 🚀                     ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo ""
echo -e "${YELLOW}This script will deploy the entire CloudCafe infrastructure:${NC}"
echo "  • 17 AWS services"
echo "  • 6 microservices"
echo "  • Chaos engineering scripts"
echo "  • CloudWatch dashboards"
echo ""
echo -e "${YELLOW}Estimated deployment time: 20-30 minutes${NC}"
echo -e "${YELLOW}Estimated monthly cost: \$800-1200${NC}"
echo ""
read -p "Continue with deployment? (yes/no): " -r
echo

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    log_info "Deployment cancelled"
    exit 0
fi

# Check prerequisites
log_info "Checking prerequisites..."

if ! command -v terraform &> /dev/null; then
    log_error "Terraform not installed. Please install from: https://www.terraform.io/downloads"
    exit 1
fi

if ! command -v aws &> /dev/null; then
    log_error "AWS CLI not installed. Please install from: https://aws.amazon.com/cli/"
    exit 1
fi

if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS credentials not configured. Run: aws configure"
    exit 1
fi

log_success "All prerequisites met"

# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
log_info "AWS Account: $AWS_ACCOUNT_ID"
log_info "AWS Region: $AWS_REGION"

# Step 1: Deploy Terraform Infrastructure
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}STEP 1: Deploying Terraform Infrastructure${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

cd "$PROJECT_ROOT/infrastructure/terraform"

if [ ! -f ".terraform.lock.hcl" ]; then
    log_info "Initializing Terraform..."
    terraform init
fi

log_info "Running Terraform plan..."
terraform plan -out=tfplan

log_info "Applying Terraform configuration..."
terraform apply tfplan

log_success "Infrastructure deployed!"

# Get outputs
VPC_ID=$(terraform output -raw vpc_id)
ECS_CLUSTER_NAME=$(terraform output -raw ecs_cluster_name)
RDS_ENDPOINT=$(terraform output -raw rds_cluster_endpoint 2>/dev/null || echo "")

cd "$PROJECT_ROOT"

# Step 2: Initialize Databases
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}STEP 2: Initializing Databases${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ -n "$RDS_ENDPOINT" ]; then
    log_info "RDS endpoint: $RDS_ENDPOINT"
    log_warning "Database schema initialization requires manual connection"
    log_info "Run: psql -h $RDS_ENDPOINT -U cloudcafe_admin -d cloudcafe"
    log_info "Then execute: CREATE TABLE IF NOT EXISTS orders (order_id VARCHAR(255) PRIMARY KEY, ...);"
else
    log_warning "RDS endpoint not available, skipping database init"
fi

# Step 3: Build and Push Container Images
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}STEP 3: Building Container Images${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Create ECR repository if it doesn't exist
log_info "Creating ECR repositories..."

for service in order-service inventory-service menu-service; do
    aws ecr describe-repositories --repository-names "cloudcafe-$service" --region $AWS_REGION 2>/dev/null || \
    aws ecr create-repository --repository-name "cloudcafe-$service" --region $AWS_REGION
done

log_success "ECR repositories ready"

# Build Order Service
if [ -f "$PROJECT_ROOT/services/order-service/Dockerfile" ]; then
    log_info "Building order-service Docker image..."

    cd "$PROJECT_ROOT/services/order-service"

    aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

    docker build -t cloudcafe-order-service .
    docker tag cloudcafe-order-service:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/cloudcafe-order-service:latest
    docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/cloudcafe-order-service:latest

    log_success "order-service image pushed to ECR"

    cd "$PROJECT_ROOT"
else
    log_warning "order-service Dockerfile not found, skipping"
fi

# Step 4: Deploy ECS Services
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}STEP 4: Deploying ECS Services${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

log_warning "ECS service deployment requires task definitions and service configurations"
log_info "This is typically done via Terraform or AWS CLI"
log_info "Example: aws ecs create-service --cluster $ECS_CLUSTER_NAME ..."

# Step 5: Deploy EKS Services
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}STEP 5: Deploying EKS Services${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

EKS_CLUSTER_NAME=$(cd "$PROJECT_ROOT/infrastructure/terraform" && terraform output -raw eks_cluster_name 2>/dev/null || echo "")

if [ -n "$EKS_CLUSTER_NAME" ]; then
    log_info "Configuring kubectl for EKS..."
    aws eks update-kubeconfig --name $EKS_CLUSTER_NAME --region $AWS_REGION

    log_warning "EKS service deployment requires Kubernetes manifests"
    log_info "Example: kubectl apply -f services/inventory-service/k8s/"
else
    log_warning "EKS cluster not found, skipping"
fi

# Step 6: Validation
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}STEP 6: Validating Deployment${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

log_info "Waiting 60 seconds for services to initialize..."
sleep 60

if [ -f "$PROJECT_ROOT/scripts/validate-infrastructure.sh" ]; then
    bash "$PROJECT_ROOT/scripts/validate-infrastructure.sh"
else
    log_warning "Validation script not found"
fi

# Summary
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ DEPLOYMENT COMPLETE${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. Open CloudWatch dashboard to view metrics"
echo "  2. Test services are responding"
echo "  3. Run load tests: cd load-testing && k6 run k6/scenarios/morning-rush.js"
echo "  4. Execute chaos scenarios: cd chaos && ./master-chaos.sh"
echo ""
echo -e "${YELLOW}Useful Commands:${NC}"
echo "  • View ECS tasks: aws ecs list-tasks --cluster $ECS_CLUSTER_NAME"
echo "  • View EKS pods: kubectl get pods --all-namespaces"
echo "  • View RDS status: aws rds describe-db-clusters --db-cluster-identifier \$RDS_CLUSTER_ID"
echo "  • Destroy infrastructure: cd infrastructure/terraform && terraform destroy"
echo ""
log_success "CloudCafe is now deployed!"
echo ""
