variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
}

variable "alb_dns_name" {
  description = "Application Load Balancer DNS name"
  type        = string
}

variable "api_gateway_url" {
  description = "API Gateway invocation URL"
  type        = string
}

variable "enable_waf" {
  description = "Enable WAF for CloudFront"
  type        = bool
  default     = true
}

variable "price_class" {
  description = "CloudFront distribution price class"
  type        = string
  default     = "PriceClass_100" # US, Canada, Europe
}
