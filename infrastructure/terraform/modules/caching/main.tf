# ElastiCache Redis Replication Group
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id       = "${var.project_name}-redis-${var.environment}"
  description                = "CloudCafe Redis cache cluster"
  engine                     = "redis"
  engine_version             = "7.0"
  node_type                  = var.elasticache_node_type
  num_cache_clusters         = var.elasticache_num_cache_nodes
  parameter_group_name       = "default.redis7"
  subnet_group_name          = var.elasticache_subnet_group_name
  security_group_ids         = [var.elasticache_security_group_id]
  port                       = 6379
  automatic_failover_enabled = var.elasticache_num_cache_nodes > 1

  tags = {
    Name        = "${var.project_name}-redis-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# MemoryDB Subnet Group
resource "aws_memorydb_subnet_group" "main" {
  name       = "${var.project_name}-memorydb-subnet-${var.environment}"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name        = "${var.project_name}-memorydb-subnet-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# Random password for MemoryDB
resource "random_password" "memorydb_password" {
  length  = 32
  special = false
}

# MemoryDB ACL
resource "aws_memorydb_acl" "main" {
  name = "${var.project_name}-memorydb-acl-${var.environment}"

  user_names = [aws_memorydb_user.admin.id]

  tags = {
    Name        = "${var.project_name}-memorydb-acl-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# MemoryDB User
resource "aws_memorydb_user" "admin" {
  user_name     = "admin"
  access_string = "on ~* &* +@all"

  authentication_mode {
    type      = "password"
    passwords = [random_password.memorydb_password.result]
  }

  tags = {
    Name        = "${var.project_name}-memorydb-user-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# MemoryDB Cluster
resource "aws_memorydb_cluster" "main" {
  name               = "${var.project_name}-memorydb-${var.environment}"
  node_type          = var.memorydb_node_type
  num_shards         = var.memorydb_num_shards
  num_replicas_per_shard = var.memorydb_num_replicas_per_shard
  acl_name           = aws_memorydb_acl.main.id
  subnet_group_name  = aws_memorydb_subnet_group.main.id
  security_group_ids = [var.elasticache_security_group_id]
  port               = 6379
  tls_enabled        = true

  tags = {
    Name        = "${var.project_name}-memorydb-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# Store MemoryDB password in Secrets Manager
resource "aws_secretsmanager_secret" "memorydb_password" {
  name = "${var.project_name}/memorydb/admin-password-${var.environment}"

  tags = {
    Name        = "${var.project_name}-memorydb-password-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "memorydb_password" {
  secret_id = aws_secretsmanager_secret.memorydb_password.id
  secret_string = jsonencode({
    username = "admin"
    password = random_password.memorydb_password.result
    endpoint = aws_memorydb_cluster.main.cluster_endpoint[0].address
    port     = aws_memorydb_cluster.main.cluster_endpoint[0].port
  })
}
