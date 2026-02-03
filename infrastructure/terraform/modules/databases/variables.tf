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

variable "db_subnet_group_name" {
  description = "DB subnet group name"
  type        = string
}

variable "rds_security_group_id" {
  description = "Security group ID for RDS"
  type        = string
}

variable "documentdb_security_group_id" {
  description = "Security group ID for DocumentDB"
  type        = string
}

variable "redshift_security_group_id" {
  description = "Security group ID for Redshift"
  type        = string
}

variable "redshift_subnet_group_name" {
  description = "Redshift subnet group name"
  type        = string
}

variable "docdb_subnet_group_name" {
  description = "DocumentDB subnet group name"
  type        = string
}

# RDS Aurora PostgreSQL Variables
variable "rds_instance_class" {
  description = "Instance class for RDS Aurora"
  type        = string
  default     = "db.t3.medium"
}

variable "rds_master_username" {
  description = "Master username for RDS"
  type        = string
  default     = "cloudcafe_admin"
  sensitive   = true
}

variable "rds_database_name" {
  description = "Initial database name"
  type        = string
  default     = "cloudcafe"
}

# DocumentDB Variables
variable "documentdb_instance_class" {
  description = "Instance class for DocumentDB"
  type        = string
  default     = "db.t3.medium"
}

variable "documentdb_master_username" {
  description = "Master username for DocumentDB"
  type        = string
  default     = "docdb_admin"
  sensitive   = true
}

# Redshift Variables
variable "redshift_node_type" {
  description = "Node type for Redshift"
  type        = string
  default     = "ra3.xlplus"
}

variable "redshift_master_username" {
  description = "Master username for Redshift"
  type        = string
  default     = "redshift_admin"
  sensitive   = true
}

variable "redshift_database_name" {
  description = "Database name for Redshift"
  type        = string
  default     = "analytics"
}
