output "elasticache_cluster_id" {
  description = "ElastiCache cluster ID"
  value       = aws_elasticache_replication_group.redis.id
}

output "elasticache_endpoint" {
  description = "ElastiCache cluster endpoint"
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "elasticache_port" {
  description = "ElastiCache cluster port"
  value       = aws_elasticache_replication_group.redis.port
}

output "memorydb_cluster_name" {
  description = "MemoryDB cluster name"
  value       = aws_memorydb_cluster.main.name
}

output "memorydb_cluster_endpoint" {
  description = "MemoryDB cluster endpoint"
  value       = aws_memorydb_cluster.main.cluster_endpoint[0].address
}

output "memorydb_cluster_port" {
  description = "MemoryDB cluster port"
  value       = aws_memorydb_cluster.main.cluster_endpoint[0].port
}

output "memorydb_secret_arn" {
  description = "ARN of MemoryDB credentials secret"
  value       = aws_secretsmanager_secret.memorydb_password.arn
}
