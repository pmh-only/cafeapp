# Outputs for Frontend Apps Module

output "s3_bucket_name" {
  description = "Name of the S3 bucket hosting frontend apps"
  value       = aws_s3_bucket.frontend_apps.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.frontend_apps.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.frontend_apps.bucket_regional_domain_name
}

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.frontend_apps.id
}

output "cloudfront_distribution_arn" {
  description = "ARN of the CloudFront distribution"
  value       = aws_cloudfront_distribution.frontend_apps.arn
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.frontend_apps.domain_name
}

output "cloudfront_url" {
  description = "Full HTTPS URL of the CloudFront distribution"
  value       = "https://${aws_cloudfront_distribution.frontend_apps.domain_name}"
}

output "frontend_urls" {
  description = "URLs for all frontend applications"
  value = {
    main_portal       = "https://${aws_cloudfront_distribution.frontend_apps.domain_name}/apps.html"
    customer_web      = "https://${aws_cloudfront_distribution.frontend_apps.domain_name}/"
    barista_dashboard = "https://${aws_cloudfront_distribution.frontend_apps.domain_name}/barista/"
    mobile_app        = "https://${aws_cloudfront_distribution.frontend_apps.domain_name}/mobile/"
    admin_analytics   = "https://${aws_cloudfront_distribution.frontend_apps.domain_name}/admin/"
    staff_portal      = "https://${aws_cloudfront_distribution.frontend_apps.domain_name}/staff/"
  }
}

output "cloudfront_oai_iam_arn" {
  description = "IAM ARN of the CloudFront Origin Access Identity"
  value       = aws_cloudfront_origin_access_identity.frontend_apps.iam_arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.frontend_access.name
}
