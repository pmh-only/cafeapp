---
inclusion: auto
---

# Technology Stack

## Infrastructure as Code

- Terraform >= 1.5.0 (all infrastructure defined in `infrastructure/terraform/`)
- Modular architecture with separate modules per AWS service category

## Microservices Tech Stack

### Order Service (Python/Flask on ECS Fargate)
- Python 3.11
- Flask 3.0.0 web framework
- Gunicorn WSGI server
- Dependencies: boto3, psycopg2-binary, redis, psutil

### Inventory Service (Go on EKS)
- Go 1.21
- AWS SDK for Go v2
- gorilla/mux for routing
- go-redis for caching

### Menu Service (Node.js/Express on EKS)
- Node.js >= 20.0.0
- Express.js 4.18.2
- Mongoose for MongoDB/DocumentDB
- ioredis for caching

### Loyalty Service (Java/Spring Boot on EC2)
- Java 17 (Amazon Corretto)
- Spring Boot 3.2.1
- Spring Data JPA
- AWS SDK for Java 2.x
- Maven build system

### Payment Processor (Python Lambda)
- Python 3.11
- boto3 for AWS SDK
- SQS-triggered serverless function

### Analytics Worker (Python on EC2)
- Python 3.11
- Kinesis Consumer Library (KCL)
- pandas for data transformation
- psycopg2 for Redshift

## AWS Services (17 Total)

**Compute:** EC2, ECS Fargate, EKS, Lambda, Auto Scaling
**Networking:** ALB, NLB, VPC Lattice, CloudFront, API Gateway
**Databases:** RDS Aurora PostgreSQL, DynamoDB, DocumentDB, ElastiCache Redis, MemoryDB, Redshift
**Messaging:** SQS, Kinesis Data Streams

## Common Commands

### Infrastructure Deployment
```bash
cd infrastructure/terraform
terraform init
terraform plan
terraform apply
terraform destroy  # cleanup
```

### Service Building

**Python services:**
```bash
pip install -r requirements.txt
python app.py  # or gunicorn
```

**Go service:**
```bash
go mod download
go build -o inventory-service ./cmd/main.go
./inventory-service
```

**Node.js service:**
```bash
npm install
npm start  # production
npm run dev  # development with nodemon
npm test  # run tests
```

**Java service:**
```bash
mvn clean install
mvn spring-boot:run
java -jar target/loyalty-service.jar
```

### Docker Operations
```bash
docker build -t <service-name> .
docker tag <service-name>:latest <ecr-repo>:latest
docker push <ecr-repo>:latest
```

### Kubernetes (EKS)
```bash
kubectl apply -f k8s/deployment.yaml
kubectl get pods
kubectl logs <pod-name>
kubectl describe pod <pod-name>
```

### Testing & Validation
```bash
./scripts/validate-infrastructure.sh  # validate deployment
k6 run load-testing/k6/scenarios/morning-rush.js  # load test
./chaos/scenarios/<scenario>.sh  # chaos engineering
```

## Development Tools Required

- AWS CLI (configured with `aws configure`)
- Docker (for building service images)
- kubectl (for EKS management)
- psql (PostgreSQL client for RDS)
- redis-cli (for cache testing)
- k6 (for load testing)
