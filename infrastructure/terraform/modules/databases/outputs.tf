output "rds_cluster_id" {
  description = "RDS Aurora cluster identifier"
  value       = aws_rds_cluster.aurora_postgres.id
}

output "rds_cluster_endpoint" {
  description = "RDS Aurora cluster endpoint"
  value       = aws_rds_cluster.aurora_postgres.endpoint
}

output "rds_reader_endpoint" {
  description = "RDS Aurora reader endpoint"
  value       = aws_rds_cluster.aurora_postgres.reader_endpoint
}

output "rds_database_name" {
  description = "RDS database name"
  value       = aws_rds_cluster.aurora_postgres.database_name
}

output "rds_master_username" {
  description = "RDS master username"
  value       = var.rds_master_username
  sensitive   = true
}

output "rds_secret_arn" {
  description = "ARN of RDS credentials secret"
  value       = aws_secretsmanager_secret.rds_master_password.arn
}

output "dynamodb_menu_catalog_table_name" {
  description = "DynamoDB menu catalog table name"
  value       = aws_dynamodb_table.menu_catalog.name
}

output "dynamodb_menu_catalog_table_arn" {
  description = "DynamoDB menu catalog table ARN"
  value       = aws_dynamodb_table.menu_catalog.arn
}

output "dynamodb_active_orders_table_name" {
  description = "DynamoDB active orders table name"
  value       = aws_dynamodb_table.active_orders.name
}

output "dynamodb_active_orders_table_arn" {
  description = "DynamoDB active orders table ARN"
  value       = aws_dynamodb_table.active_orders.arn
}

output "dynamodb_store_inventory_table_name" {
  description = "DynamoDB store inventory table name"
  value       = aws_dynamodb_table.store_inventory.name
}

output "dynamodb_store_inventory_table_arn" {
  description = "DynamoDB store inventory table ARN"
  value       = aws_dynamodb_table.store_inventory.arn
}

output "documentdb_cluster_id" {
  description = "DocumentDB cluster identifier"
  value       = aws_docdb_cluster.main.id
}

output "documentdb_endpoint" {
  description = "DocumentDB cluster endpoint"
  value       = aws_docdb_cluster.main.endpoint
}

output "documentdb_reader_endpoint" {
  description = "DocumentDB reader endpoint"
  value       = aws_docdb_cluster.main.reader_endpoint
}

output "documentdb_master_username" {
  description = "DocumentDB master username"
  value       = var.documentdb_master_username
  sensitive   = true
}

output "documentdb_secret_arn" {
  description = "ARN of DocumentDB credentials secret"
  value       = aws_secretsmanager_secret.documentdb_master_password.arn
}

output "redshift_cluster_id" {
  description = "Redshift cluster identifier"
  value       = aws_redshift_cluster.main.id
}

output "redshift_endpoint" {
  description = "Redshift cluster endpoint"
  value       = aws_redshift_cluster.main.endpoint
}

output "redshift_database_name" {
  description = "Redshift database name"
  value       = aws_redshift_cluster.main.database_name
}

output "redshift_master_username" {
  description = "Redshift master username"
  value       = var.redshift_master_username
  sensitive   = true
}

output "redshift_secret_arn" {
  description = "ARN of Redshift credentials secret"
  value       = aws_secretsmanager_secret.redshift_master_password.arn
}

output "dynamodb_table_names" {
  description = "Map of DynamoDB table names for chaos scripts"
  value = {
    menu_catalog    = aws_dynamodb_table.menu_catalog.name
    active_orders   = aws_dynamodb_table.active_orders.name
    store_inventory = aws_dynamodb_table.store_inventory.name
  }
}
