# Random password for RDS
resource "random_password" "rds_master_password" {
  length  = 16
  special = true
}

# RDS Aurora PostgreSQL Cluster
resource "aws_rds_cluster" "aurora_postgres" {
  cluster_identifier      = "${var.project_name}-aurora-${var.environment}"
  engine                  = "aurora-postgresql"
  engine_version          = "15.15"
  database_name           = var.rds_database_name
  master_username         = var.rds_master_username
  master_password         = random_password.rds_master_password.result
  db_subnet_group_name    = var.db_subnet_group_name
  vpc_security_group_ids  = [var.rds_security_group_id]
  backup_retention_period = 7
  preferred_backup_window = "03:00-04:00"
  skip_final_snapshot     = true
  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = {
    Name        = "${var.project_name}-aurora-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# RDS Aurora Primary Instance
resource "aws_rds_cluster_instance" "aurora_primary" {
  identifier           = "${var.project_name}-aurora-primary-${var.environment}"
  cluster_identifier   = aws_rds_cluster.aurora_postgres.id
  instance_class       = var.rds_instance_class
  engine               = aws_rds_cluster.aurora_postgres.engine
  engine_version       = aws_rds_cluster.aurora_postgres.engine_version
  publicly_accessible  = false
  db_subnet_group_name = var.db_subnet_group_name

  performance_insights_enabled = true

  tags = {
    Name        = "${var.project_name}-aurora-primary-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# RDS Aurora Read Replica
resource "aws_rds_cluster_instance" "aurora_replica" {
  identifier           = "${var.project_name}-aurora-replica-${var.environment}"
  cluster_identifier   = aws_rds_cluster.aurora_postgres.id
  instance_class       = var.rds_instance_class
  engine               = aws_rds_cluster.aurora_postgres.engine
  engine_version       = aws_rds_cluster.aurora_postgres.engine_version
  publicly_accessible  = false
  db_subnet_group_name = var.db_subnet_group_name

  performance_insights_enabled = true

  tags = {
    Name        = "${var.project_name}-aurora-replica-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# Store RDS password in Secrets Manager
resource "aws_secretsmanager_secret" "rds_master_password" {
  name = "${var.project_name}/rds/master-password-${var.environment}"

  tags = {
    Name        = "${var.project_name}-rds-password-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "rds_master_password" {
  secret_id = aws_secretsmanager_secret.rds_master_password.id
  secret_string = jsonencode({
    username = var.rds_master_username
    password = random_password.rds_master_password.result
    endpoint = aws_rds_cluster.aurora_postgres.endpoint
    database = var.rds_database_name
  })
}

# DynamoDB Table - Menu Catalog
resource "aws_dynamodb_table" "menu_catalog" {
  name           = "${var.project_name}-menu-catalog-${var.environment}"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "item_id"
  stream_enabled = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "item_id"
    type = "S"
  }

  attribute {
    name = "category"
    type = "S"
  }

  global_secondary_index {
    name            = "CategoryIndex"
    hash_key        = "category"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = "${var.project_name}-menu-catalog-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# DynamoDB Table - Active Orders
resource "aws_dynamodb_table" "active_orders" {
  name           = "${var.project_name}-active-orders-${var.environment}"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "order_id"
  stream_enabled = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "order_id"
    type = "S"
  }

  attribute {
    name = "customer_id"
    type = "S"
  }

  attribute {
    name = "created_at"
    type = "N"
  }

  global_secondary_index {
    name            = "CustomerOrderIndex"
    hash_key        = "customer_id"
    range_key       = "created_at"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  ttl {
    enabled        = true
    attribute_name = "ttl"
  }

  tags = {
    Name        = "${var.project_name}-active-orders-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# DynamoDB Table - Store Inventory
resource "aws_dynamodb_table" "store_inventory" {
  name           = "${var.project_name}-store-inventory-${var.environment}"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "store_id"
  range_key      = "sku"
  stream_enabled = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "store_id"
    type = "S"
  }

  attribute {
    name = "sku"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = "${var.project_name}-store-inventory-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# Random password for DocumentDB
resource "random_password" "documentdb_master_password" {
  length  = 16
  special = false
}

# DocumentDB Cluster
resource "aws_docdb_cluster" "main" {
  cluster_identifier      = "${var.project_name}-docdb-${var.environment}"
  engine                  = "docdb"
  master_username         = var.documentdb_master_username
  master_password         = random_password.documentdb_master_password.result
  db_subnet_group_name    = var.docdb_subnet_group_name
  vpc_security_group_ids  = [var.documentdb_security_group_id]
  backup_retention_period = 7
  preferred_backup_window = "04:00-05:00"
  skip_final_snapshot     = true
  enabled_cloudwatch_logs_exports = ["audit", "profiler"]

  tags = {
    Name        = "${var.project_name}-docdb-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# DocumentDB Primary Instance
resource "aws_docdb_cluster_instance" "primary" {
  identifier         = "${var.project_name}-docdb-primary-${var.environment}"
  cluster_identifier = aws_docdb_cluster.main.id
  instance_class     = var.documentdb_instance_class

  tags = {
    Name        = "${var.project_name}-docdb-primary-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# DocumentDB Replica
resource "aws_docdb_cluster_instance" "replica" {
  identifier         = "${var.project_name}-docdb-replica-${var.environment}"
  cluster_identifier = aws_docdb_cluster.main.id
  instance_class     = var.documentdb_instance_class

  tags = {
    Name        = "${var.project_name}-docdb-replica-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# Store DocumentDB password in Secrets Manager
resource "aws_secretsmanager_secret" "documentdb_master_password" {
  name = "${var.project_name}/documentdb/master-password-${var.environment}"

  tags = {
    Name        = "${var.project_name}-documentdb-password-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "documentdb_master_password" {
  secret_id = aws_secretsmanager_secret.documentdb_master_password.id
  secret_string = jsonencode({
    username = var.documentdb_master_username
    password = random_password.documentdb_master_password.result
    endpoint = aws_docdb_cluster.main.endpoint
  })
}

# Random password for Redshift
resource "random_password" "redshift_master_password" {
  length  = 16
  special = true
}

# Redshift Cluster
resource "aws_redshift_cluster" "main" {
  cluster_identifier  = "${var.project_name}-redshift-${var.environment}"
  database_name       = var.redshift_database_name
  master_username     = var.redshift_master_username
  master_password     = random_password.redshift_master_password.result
  node_type           = var.redshift_node_type
  cluster_type        = "single-node"
  cluster_subnet_group_name = var.redshift_subnet_group_name
  vpc_security_group_ids    = [var.redshift_security_group_id]
  publicly_accessible = false
  skip_final_snapshot = true

  logging {
    enable = false
  }

  tags = {
    Name        = "${var.project_name}-redshift-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# Store Redshift password in Secrets Manager
resource "aws_secretsmanager_secret" "redshift_master_password" {
  name = "${var.project_name}/redshift/master-password-${var.environment}"

  tags = {
    Name        = "${var.project_name}-redshift-password-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "redshift_master_password" {
  secret_id = aws_secretsmanager_secret.redshift_master_password.id
  secret_string = jsonencode({
    username = var.redshift_master_username
    password = random_password.redshift_master_password.result
    endpoint = aws_redshift_cluster.main.endpoint
    database = var.redshift_database_name
  })
}
