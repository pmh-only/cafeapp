output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "database_subnet_ids" {
  description = "List of database subnet IDs"
  value       = aws_subnet.database[*].id
}

output "alb_security_group_id" {
  description = "Security group ID for ALB"
  value       = aws_security_group.alb.id
}

output "ecs_task_security_group_id" {
  description = "Security group ID for ECS tasks"
  value       = aws_security_group.ecs_tasks.id
}

output "eks_node_security_group_id" {
  description = "Security group ID for EKS nodes"
  value       = aws_security_group.eks_nodes.id
}

output "ec2_security_group_id" {
  description = "Security group ID for EC2 instances"
  value       = aws_security_group.ec2.id
}

output "rds_security_group_id" {
  description = "Security group ID for RDS"
  value       = aws_security_group.rds.id
}

output "documentdb_security_group_id" {
  description = "Security group ID for DocumentDB"
  value       = aws_security_group.documentdb.id
}

output "elasticache_security_group_id" {
  description = "Security group ID for ElastiCache"
  value       = aws_security_group.elasticache.id
}

output "redshift_security_group_id" {
  description = "Security group ID for Redshift"
  value       = aws_security_group.redshift.id
}

output "db_subnet_group_name" {
  description = "DB subnet group name for RDS"
  value       = aws_db_subnet_group.main.name
}

output "elasticache_subnet_group_name" {
  description = "ElastiCache subnet group name"
  value       = aws_elasticache_subnet_group.main.name
}

output "redshift_subnet_group_name" {
  description = "Redshift subnet group name"
  value       = aws_redshift_subnet_group.main.name
}

output "docdb_subnet_group_name" {
  description = "DocumentDB subnet group name"
  value       = aws_docdb_subnet_group.main.name
}
