output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (for chaos scripts)"
  value       = aws_cloudfront_distribution.main.id
}

output "cloudfront_distribution_arn" {
  description = "CloudFront distribution ARN"
  value       = aws_cloudfront_distribution.main.arn
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "cloudfront_hosted_zone_id" {
  description = "CloudFront distribution hosted zone ID"
  value       = aws_cloudfront_distribution.main.hosted_zone_id
}

output "cloudfront_url" {
  description = "CloudFront distribution URL"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

output "waf_web_acl_id" {
  description = "WAF Web ACL ID"
  value       = var.enable_waf ? aws_wafv2_web_acl.cloudfront[0].id : null
}

output "waf_web_acl_arn" {
  description = "WAF Web ACL ARN"
  value       = var.enable_waf ? aws_wafv2_web_acl.cloudfront[0].arn : null
}

output "logs_bucket_name" {
  description = "S3 bucket name for CloudFront logs"
  value       = aws_s3_bucket.logs.id
}

output "logs_bucket_arn" {
  description = "S3 bucket ARN for CloudFront logs"
  value       = aws_s3_bucket.logs.arn
}
