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

variable "elasticache_subnet_group_name" {
  description = "ElastiCache subnet group name"
  type        = string
}

variable "elasticache_security_group_id" {
  description = "Security group ID for ElastiCache"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for MemoryDB"
  type        = list(string)
}

variable "elasticache_node_type" {
  description = "Node type for ElastiCache"
  type        = string
  default     = "cache.t3.medium"
}

variable "elasticache_num_cache_nodes" {
  description = "Number of cache nodes for ElastiCache"
  type        = number
  default     = 2
}

variable "memorydb_node_type" {
  description = "Node type for MemoryDB"
  type        = string
  default     = "db.t4g.small"
}

variable "memorydb_num_shards" {
  description = "Number of shards for MemoryDB"
  type        = number
  default     = 1
}

variable "memorydb_num_replicas_per_shard" {
  description = "Number of replicas per shard for MemoryDB"
  type        = number
  default     = 0
}
