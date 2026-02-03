variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
}

variable "kinesis_order_events_shard_count" {
  description = "Number of shards for order events Kinesis stream"
  type        = number
  default     = 4
}

variable "kinesis_analytics_events_shard_count" {
  description = "Number of shards for analytics events Kinesis stream"
  type        = number
  default     = 2
}
