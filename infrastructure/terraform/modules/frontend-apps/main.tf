# CloudCafe Frontend Applications Infrastructure
# Deploys multiple frontend apps to S3 with CloudFront distribution

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# S3 Bucket for Frontend Applications
resource "aws_s3_bucket" "frontend_apps" {
  bucket = "${var.project_name}-frontend-apps-${var.environment}"

  tags = {
    Name        = "${var.project_name}-frontend-apps-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Purpose     = "Frontend Applications Hosting"
  }
}

# Block public access at bucket level (CloudFront will access via OAI)
resource "aws_s3_bucket_public_access_block" "frontend_apps" {
  bucket = aws_s3_bucket.frontend_apps.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning for rollback capability
resource "aws_s3_bucket_versioning" "frontend_apps" {
  bucket = aws_s3_bucket.frontend_apps.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "frontend_apps" {
  bucket = aws_s3_bucket.frontend_apps.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Lifecycle rules for old versions
resource "aws_s3_bucket_lifecycle_configuration" "frontend_apps" {
  bucket = aws_s3_bucket.frontend_apps.id

  rule {
    id     = "delete-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# CloudFront Origin Access Identity
resource "aws_cloudfront_origin_access_identity" "frontend_apps" {
  comment = "OAI for ${var.project_name} frontend apps"
}

# S3 Bucket Policy for CloudFront OAI
resource "aws_s3_bucket_policy" "frontend_apps" {
  bucket = aws_s3_bucket.frontend_apps.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOAI"
        Effect = "Allow"
        Principal = {
          AWS = aws_cloudfront_origin_access_identity.frontend_apps.iam_arn
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.frontend_apps.arn}/*"
      }
    ]
  })
}

# CloudFront Distribution for Frontend Apps
resource "aws_cloudfront_distribution" "frontend_apps" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.project_name} Frontend Applications"
  default_root_object = "index.html"
  price_class         = var.cloudfront_price_class

  origin {
    domain_name = aws_s3_bucket.frontend_apps.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.frontend_apps.id}"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.frontend_apps.cloudfront_access_identity_path
    }
  }

  # Default cache behavior (Customer Web App)
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.frontend_apps.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
  }

  # Cache behavior for Barista Dashboard
  ordered_cache_behavior {
    path_pattern     = "/barista/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.frontend_apps.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 300  # 5 minutes for dashboard
    max_ttl                = 3600
    compress               = true
  }

  # Cache behavior for Mobile App
  ordered_cache_behavior {
    path_pattern     = "/mobile/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.frontend_apps.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
  }

  # Cache behavior for Admin Analytics
  ordered_cache_behavior {
    path_pattern     = "/admin/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.frontend_apps.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 300  # 5 minutes for analytics
    max_ttl                = 3600
    compress               = true
  }

  # Cache behavior for Staff Portal
  ordered_cache_behavior {
    path_pattern     = "/staff/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.frontend_apps.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 300  # 5 minutes for staff portal
    max_ttl                = 3600
    compress               = true
  }

  # Custom error responses for SPA routing
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  tags = {
    Name        = "${var.project_name}-frontend-apps-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# Upload Customer Web App
resource "aws_s3_object" "customer_web" {
  bucket       = aws_s3_bucket.frontend_apps.id
  key          = "index.html"
  source       = "${var.frontend_source_path}/customer-web/index.html"
  etag         = filemd5("${var.frontend_source_path}/customer-web/index.html")
  content_type = "text/html"

  cache_control = "max-age=3600"

  tags = {
    App = "customer-web"
  }
}

# Upload Barista Dashboard
resource "aws_s3_object" "barista_dashboard" {
  bucket       = aws_s3_bucket.frontend_apps.id
  key          = "barista/index.html"
  source       = "${var.frontend_source_path}/barista-dashboard/index.html"
  etag         = filemd5("${var.frontend_source_path}/barista-dashboard/index.html")
  content_type = "text/html"

  cache_control = "max-age=300"

  tags = {
    App = "barista-dashboard"
  }
}

# Upload Mobile App
resource "aws_s3_object" "mobile_app" {
  bucket       = aws_s3_bucket.frontend_apps.id
  key          = "mobile/index.html"
  source       = "${var.frontend_source_path}/mobile-app/index.html"
  etag         = filemd5("${var.frontend_source_path}/mobile-app/index.html")
  content_type = "text/html"

  cache_control = "max-age=3600"

  tags = {
    App = "mobile-app"
  }
}

# Upload Admin Analytics
resource "aws_s3_object" "admin_analytics" {
  bucket       = aws_s3_bucket.frontend_apps.id
  key          = "admin/index.html"
  source       = "${var.frontend_source_path}/admin-analytics/index.html"
  etag         = filemd5("${var.frontend_source_path}/admin-analytics/index.html")
  content_type = "text/html"

  cache_control = "max-age=300"

  tags = {
    App = "admin-analytics"
  }
}

# Upload Staff Portal HTML
resource "aws_s3_object" "staff_portal_html" {
  bucket       = aws_s3_bucket.frontend_apps.id
  key          = "staff/index.html"
  source       = "${var.frontend_source_path}/staff-portal/index.html"
  etag         = filemd5("${var.frontend_source_path}/staff-portal/index.html")
  content_type = "text/html"

  cache_control = "max-age=300"

  tags = {
    App = "staff-portal"
  }
}

# Upload Staff Portal JS
resource "aws_s3_object" "staff_portal_js" {
  bucket       = aws_s3_bucket.frontend_apps.id
  key          = "staff/staff-portal.js"
  source       = "${var.frontend_source_path}/staff-portal/staff-portal.js"
  etag         = filemd5("${var.frontend_source_path}/staff-portal/staff-portal.js")
  content_type = "application/javascript"

  cache_control = "max-age=300"

  tags = {
    App = "staff-portal"
  }
}

# Upload Main Portal Page
resource "aws_s3_object" "main_portal" {
  bucket       = aws_s3_bucket.frontend_apps.id
  key          = "apps.html"
  content_type = "text/html"
  cache_control = "max-age=300"

  content = templatefile("${path.module}/templates/apps-portal.html", {
    cloudfront_url = "https://${aws_cloudfront_distribution.frontend_apps.domain_name}"
  })

  tags = {
    App = "main-portal"
  }
}

# CloudWatch Log Group for monitoring
resource "aws_cloudwatch_log_group" "frontend_access" {
  name              = "/aws/cloudfront/${var.project_name}-frontend-apps-${var.environment}"
  retention_in_days = 7

  tags = {
    Name        = "${var.project_name}-frontend-logs-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

# CloudWatch Alarms for monitoring
resource "aws_cloudwatch_metric_alarm" "high_4xx_errors" {
  alarm_name          = "${var.project_name}-frontend-high-4xx-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "4xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = "300"
  statistic           = "Average"
  threshold           = "5"
  alarm_description   = "This metric monitors CloudFront 4xx error rate"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DistributionId = aws_cloudfront_distribution.frontend_apps.id
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_metric_alarm" "high_5xx_errors" {
  alarm_name          = "${var.project_name}-frontend-high-5xx-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "5xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = "300"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "This metric monitors CloudFront 5xx error rate"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DistributionId = aws_cloudfront_distribution.frontend_apps.id
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}
