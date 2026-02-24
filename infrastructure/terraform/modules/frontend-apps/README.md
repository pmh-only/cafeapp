# CloudCafe Frontend Applications Terraform Module

This Terraform module deploys the CloudCafe frontend applications to AWS S3 and CloudFront.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    CloudFront CDN                       │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Origin Access Identity (OAI)                    │  │
│  │  - Secure access to S3                           │  │
│  │  - HTTPS only                                    │  │
│  │  - Global edge locations                         │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│                    S3 Bucket                            │
│  ┌──────────────────────────────────────────────────┐  │
│  │  /index.html          (Customer Web)             │  │
│  │  /barista/index.html  (Barista Dashboard)        │  │
│  │  /mobile/index.html   (Mobile App)               │  │
│  │  /admin/index.html    (Admin Analytics)          │  │
│  │  /apps.html           (Main Portal)              │  │
│  └──────────────────────────────────────────────────┘  │
│  - Versioning enabled                                   │
│  - Server-side encryption                               │
│  - Private (OAI access only)                            │
└─────────────────────────────────────────────────────────┘
```

## Features

### Security
- ✅ S3 bucket is private (no public access)
- ✅ CloudFront Origin Access Identity (OAI) for secure access
- ✅ HTTPS only (redirect HTTP to HTTPS)
- ✅ Server-side encryption (AES256)
- ✅ TLS 1.2+ minimum

### Performance
- ✅ Global CDN with edge locations
- ✅ Gzip compression enabled
- ✅ Optimized cache TTLs per application
- ✅ Custom error pages for SPA routing

### Reliability
- ✅ S3 versioning for rollback capability
- ✅ CloudWatch monitoring and alarms
- ✅ Lifecycle policies for old versions
- ✅ Multi-region edge caching

### Observability
- ✅ CloudWatch Logs for access patterns
- ✅ Alarms for 4xx and 5xx errors
- ✅ Metrics for cache hit ratio
- ✅ Distribution monitoring

## Resources Created

### S3 Resources
- `aws_s3_bucket` - Frontend applications bucket
- `aws_s3_bucket_public_access_block` - Block public access
- `aws_s3_bucket_versioning` - Enable versioning
- `aws_s3_bucket_server_side_encryption_configuration` - Encryption
- `aws_s3_bucket_lifecycle_configuration` - Lifecycle rules
- `aws_s3_bucket_policy` - OAI access policy
- `aws_s3_object` (5x) - Frontend HTML files

### CloudFront Resources
- `aws_cloudfront_origin_access_identity` - OAI for S3 access
- `aws_cloudfront_distribution` - CDN distribution
  - Default behavior (Customer Web)
  - Ordered behavior for /barista/*
  - Ordered behavior for /mobile/*
  - Ordered behavior for /admin/*

### Monitoring Resources
- `aws_cloudwatch_log_group` - Access logs
- `aws_cloudwatch_metric_alarm` (2x) - Error rate alarms

## Cache Configuration

Different cache TTLs for different application types:

| Application | Path | Default TTL | Max TTL | Rationale |
|------------|------|-------------|---------|-----------|
| Customer Web | / | 1 hour | 24 hours | Static content, infrequent changes |
| Barista Dashboard | /barista/* | 5 minutes | 1 hour | Real-time data, frequent updates |
| Mobile App | /mobile/* | 1 hour | 24 hours | Static content, mobile optimized |
| Admin Analytics | /admin/* | 5 minutes | 1 hour | Real-time metrics, frequent updates |
| Main Portal | /apps.html | 5 minutes | 1 hour | Entry point, moderate caching |

## Usage

### Basic Usage

```hcl
module "frontend_apps" {
  source = "./modules/frontend-apps"

  project_name           = "cloudcafe"
  environment            = "dev"
  frontend_source_path   = "../../frontends"
  cloudfront_price_class = "PriceClass_100"
}
```

### With Custom Configuration

```hcl
module "frontend_apps" {
  source = "./modules/frontend-apps"

  project_name           = "cloudcafe"
  environment            = "prod"
  frontend_source_path   = "../../frontends"
  cloudfront_price_class = "PriceClass_All"  # Global distribution
  enable_waf             = true               # Enable WAF (us-east-1 only)

  tags = {
    Component  = "Frontend"
    CostCenter = "Engineering"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| project_name | Name of the project | string | "cloudcafe" | no |
| environment | Environment name | string | "dev" | no |
| frontend_source_path | Path to frontend source files | string | "../../frontends" | no |
| cloudfront_price_class | CloudFront price class | string | "PriceClass_100" | no |
| enable_waf | Enable AWS WAF | bool | false | no |
| tags | Additional tags | map(string) | {} | no |

## Outputs

| Name | Description |
|------|-------------|
| s3_bucket_name | Name of the S3 bucket |
| s3_bucket_arn | ARN of the S3 bucket |
| cloudfront_distribution_id | CloudFront distribution ID |
| cloudfront_domain_name | CloudFront domain name |
| cloudfront_url | Full HTTPS URL |
| frontend_urls | Map of all frontend URLs |

## Deployment

### Initial Deployment

```bash
cd infrastructure/terraform

# Initialize Terraform
terraform init

# Plan the deployment
terraform plan

# Apply the changes
terraform apply
```

### Update Frontend Files

When you update frontend files, Terraform will detect changes via file MD5 hashes:

```bash
# Terraform will automatically detect file changes
terraform plan

# Apply updates
terraform apply

# Invalidate CloudFront cache
aws cloudfront create-invalidation \
  --distribution-id $(terraform output -raw frontend_cloudfront_id) \
  --paths "/*"
```

### Rollback

Thanks to S3 versioning, you can rollback to previous versions:

```bash
# List object versions
aws s3api list-object-versions \
  --bucket $(terraform output -raw frontend_s3_bucket) \
  --prefix "index.html"

# Restore previous version
aws s3api copy-object \
  --bucket $(terraform output -raw frontend_s3_bucket) \
  --copy-source "bucket/index.html?versionId=VERSION_ID" \
  --key "index.html"
```

## Monitoring

### CloudWatch Metrics

The module creates alarms for:
- **4xx Error Rate**: Triggers if > 5% for 10 minutes
- **5xx Error Rate**: Triggers if > 1% for 10 minutes

### View Metrics

```bash
# Get distribution ID
DIST_ID=$(terraform output -raw frontend_cloudfront_id)

# View CloudFront metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/CloudFront \
  --metric-name Requests \
  --dimensions Name=DistributionId,Value=$DIST_ID \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-02T00:00:00Z \
  --period 3600 \
  --statistics Sum
```

## Cost Optimization

### CloudFront Price Classes

- **PriceClass_100**: US, Canada, Europe (~$0.085/GB)
- **PriceClass_200**: + Asia, Africa, South America (~$0.120/GB)
- **PriceClass_All**: All edge locations (~$0.170/GB)

### Estimated Monthly Costs

For 100GB data transfer and 1M requests:

| Component | Cost |
|-----------|------|
| S3 Storage (10GB) | $0.23 |
| S3 Requests (1M GET) | $0.40 |
| CloudFront (100GB) | $8.50 |
| CloudFront Requests (1M) | $1.00 |
| **Total** | **~$10.13/month** |

## Security Best Practices

### Implemented
- ✅ S3 bucket is private
- ✅ CloudFront OAI for access control
- ✅ HTTPS only (no HTTP)
- ✅ Server-side encryption
- ✅ TLS 1.2+ minimum
- ✅ No public bucket policies

### Recommended
- [ ] Add custom domain with ACM certificate
- [ ] Enable CloudFront access logs
- [ ] Add WAF rules (if in us-east-1)
- [ ] Implement CSP headers
- [ ] Add rate limiting

## Troubleshooting

### Issue: 403 Forbidden

**Cause**: OAI doesn't have permission to access S3

**Solution**:
```bash
# Verify bucket policy
aws s3api get-bucket-policy \
  --bucket $(terraform output -raw frontend_s3_bucket)

# Reapply Terraform
terraform apply
```

### Issue: Stale Content

**Cause**: CloudFront cache not invalidated

**Solution**:
```bash
# Invalidate cache
aws cloudfront create-invalidation \
  --distribution-id $(terraform output -raw frontend_cloudfront_id) \
  --paths "/*"
```

### Issue: Slow Updates

**Cause**: CloudFront propagation delay

**Solution**: Wait 5-10 minutes for distribution updates to propagate globally

## Examples

### Access Frontend URLs

```bash
# Get all URLs
terraform output frontend_urls

# Open customer web app
open $(terraform output -raw frontend_cloudfront_url)

# Open barista dashboard
open "$(terraform output -raw frontend_cloudfront_url)/barista/"
```

### Update Single File

```bash
# Update file in S3
aws s3 cp frontends/customer-web/index.html \
  s3://$(terraform output -raw frontend_s3_bucket)/index.html

# Invalidate specific path
aws cloudfront create-invalidation \
  --distribution-id $(terraform output -raw frontend_cloudfront_id) \
  --paths "/index.html"
```

## Integration with CI/CD

### GitHub Actions Example

```yaml
name: Deploy Frontends

on:
  push:
    branches: [main]
    paths:
      - 'frontends/**'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Configure AWS
        uses: aws-actions/configure-aws-credentials@v1
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ap-northeast-2
      
      - name: Deploy with Terraform
        run: |
          cd infrastructure/terraform
          terraform init
          terraform apply -auto-approve
      
      - name: Invalidate CloudFront
        run: |
          DIST_ID=$(cd infrastructure/terraform && terraform output -raw frontend_cloudfront_id)
          aws cloudfront create-invalidation --distribution-id $DIST_ID --paths "/*"
```

## License

MIT License - CloudCafe Team

## Support

For issues or questions:
- **Infrastructure**: infra@cloudcafe.com
- **Frontend**: frontend@cloudcafe.com
- **DevOps**: devops@cloudcafe.com

---

**Built with ☕ and ❤️ by the CloudCafe Team**

**Region**: ap-northeast-2 (Seoul, South Korea)  
**Managed By**: Terraform  
**Status**: Production Ready 🚀
