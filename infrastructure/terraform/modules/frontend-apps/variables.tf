# Variables for Frontend Apps Module

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "cloudcafe"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "frontend_source_path" {
  description = "Path to frontend source files"
  type        = string
  default     = "../../frontends"
}

variable "cloudfront_price_class" {
  description = "CloudFront price class"
  type        = string
  default     = "PriceClass_100"  # US, Canada, Europe

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.cloudfront_price_class)
    error_message = "Price class must be PriceClass_100, PriceClass_200, or PriceClass_All"
  }
}

variable "enable_waf" {
  description = "Enable AWS WAF for CloudFront"
  type        = bool
  default     = false  # Disabled for non-us-east-1 regions
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
