variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for Lambda"
  type        = list(string)
}

variable "payment_processing_queue_arn" {
  description = "ARN of payment processing SQS queue"
  type        = string
}

variable "payment_processing_queue_url" {
  description = "URL of payment processing SQS queue"
  type        = string
}

variable "analytics_events_stream_arn" {
  description = "ARN of analytics Kinesis stream"
  type        = string
}

variable "analytics_events_stream_name" {
  description = "Name of analytics Kinesis stream"
  type        = string
}

variable "alb_arn" {
  description = "ARN of Application Load Balancer for API Gateway integration"
  type        = string
}

variable "alb_dns_name" {
  description = "DNS name of Application Load Balancer"
  type        = string
}

variable "nlb_arn" {
  description = "ARN of Network Load Balancer for API Gateway VPC Link"
  type        = string
}

variable "alb_listener_arn" {
  description = "ARN of ALB listener for API Gateway integration"
  type        = string
}

variable "lambda_payment_memory_size" {
  description = "Memory size for payment processor Lambda"
  type        = number
  default     = 512
}

variable "lambda_analytics_memory_size" {
  description = "Memory size for analytics writer Lambda"
  type        = number
  default     = 256
}
