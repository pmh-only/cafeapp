# Network Outputs
output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}

output "ecs_task_security_group_id" {
  description = "Security group ID for ECS tasks (for chaos scripts)"
  value       = module.networking.ecs_task_security_group_id
}

# Compute Outputs
output "ecs_cluster_name" {
  description = "ECS cluster name (for chaos scripts)"
  value       = module.compute.ecs_cluster_name
}

output "ecs_cluster_arn" {
  description = "ECS cluster ARN"
  value       = module.compute.ecs_cluster_arn
}

output "eks_cluster_name" {
  description = "EKS cluster name (for chaos scripts)"
  value       = module.compute.eks_cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.compute.eks_cluster_endpoint
}

output "ec2_autoscaling_group_name" {
  description = "EC2 Auto Scaling Group name"
  value       = module.compute.ec2_autoscaling_group_name
}

# Database Outputs
output "rds_cluster_id" {
  description = "RDS Aurora cluster identifier (for chaos scripts)"
  value       = module.databases.rds_cluster_id
}

output "rds_cluster_endpoint" {
  description = "RDS Aurora cluster endpoint"
  value       = module.databases.rds_cluster_endpoint
}

output "dynamodb_table_names" {
  description = "Map of DynamoDB table names (for chaos scripts)"
  value       = module.databases.dynamodb_table_names
}

output "documentdb_cluster_id" {
  description = "DocumentDB cluster identifier"
  value       = module.databases.documentdb_cluster_id
}

output "documentdb_endpoint" {
  description = "DocumentDB endpoint"
  value       = module.databases.documentdb_endpoint
}

output "redshift_cluster_id" {
  description = "Redshift cluster identifier"
  value       = module.databases.redshift_cluster_id
}

output "redshift_endpoint" {
  description = "Redshift endpoint"
  value       = module.databases.redshift_endpoint
}

# Caching Outputs
output "elasticache_cluster_id" {
  description = "ElastiCache cluster ID (for chaos scripts)"
  value       = module.caching.elasticache_cluster_id
}

output "elasticache_endpoint" {
  description = "ElastiCache endpoint"
  value       = module.caching.elasticache_endpoint
}

output "memorydb_cluster_name" {
  description = "MemoryDB cluster name (for chaos scripts)"
  value       = module.caching.memorydb_cluster_name
}

output "memorydb_cluster_endpoint" {
  description = "MemoryDB endpoint"
  value       = module.caching.memorydb_cluster_endpoint
}

# Messaging Outputs
output "sqs_queue_urls" {
  description = "Map of SQS queue URLs (for chaos scripts)"
  value       = module.messaging.sqs_queue_urls
}

output "kinesis_stream_names" {
  description = "List of Kinesis stream names (for chaos scripts)"
  value       = module.messaging.kinesis_stream_names
}

output "order_events_stream_name" {
  description = "Kinesis order events stream name"
  value       = module.messaging.order_events_stream_name
}

output "payment_processing_queue_url" {
  description = "SQS payment processing queue URL"
  value       = module.messaging.payment_processing_queue_url
}

# Load Balancing Outputs
output "alb_arn" {
  description = "Application Load Balancer ARN (for chaos scripts)"
  value       = module.loadbalancing.alb_arn
}

output "alb_dns_name" {
  description = "Application Load Balancer DNS name"
  value       = module.loadbalancing.alb_dns_name
}

output "nlb_arn" {
  description = "Network Load Balancer ARN (for chaos scripts)"
  value       = module.loadbalancing.nlb_arn
}

output "nlb_dns_name" {
  description = "Network Load Balancer DNS name"
  value       = module.loadbalancing.nlb_dns_name
}

output "vpc_lattice_service_network_arn" {
  description = "VPC Lattice service network ARN (for chaos scripts)"
  value       = module.loadbalancing.vpc_lattice_service_network_arn
}

# Serverless Outputs
output "payment_processor_function_name" {
  description = "Payment processor Lambda function name"
  value       = module.serverless.payment_processor_function_name
}

output "analytics_writer_function_name" {
  description = "Analytics writer Lambda function name"
  value       = module.serverless.analytics_writer_function_name
}

output "api_gateway_url" {
  description = "API Gateway invocation URL"
  value       = module.serverless.api_gateway_url
}

# Frontend Outputs
output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (for chaos scripts)"
  value       = module.frontend.cloudfront_distribution_id
}

output "cloudfront_url" {
  description = "CloudFront distribution URL"
  value       = module.frontend.cloudfront_url
}
