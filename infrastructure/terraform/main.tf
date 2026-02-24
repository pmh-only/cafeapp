terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Networking Module
module "networking" {
  source = "./modules/networking"

  project_name       = var.project_name
  environment        = var.environment
  availability_zones = var.availability_zones
}

# Frontend Applications Module
module "frontend_apps" {
  source = "./modules/frontend-apps"

  project_name           = var.project_name
  environment            = var.environment
  frontend_source_path   = "${path.root}/../../frontends"
  cloudfront_price_class = "PriceClass_100"
  enable_waf             = false  # WAF requires us-east-1

  tags = {
    Component = "Frontend"
    Deployment = "Terraform"
  }
}

# Databases Module
module "databases" {
  source = "./modules/databases"

  project_name                  = var.project_name
  environment                   = var.environment
  vpc_id                        = module.networking.vpc_id
  db_subnet_group_name          = module.networking.db_subnet_group_name
  rds_security_group_id         = module.networking.rds_security_group_id
  documentdb_security_group_id  = module.networking.documentdb_security_group_id
  redshift_security_group_id    = module.networking.redshift_security_group_id
  redshift_subnet_group_name    = module.networking.redshift_subnet_group_name
  docdb_subnet_group_name       = module.networking.docdb_subnet_group_name
}

# Caching Module
module "caching" {
  source = "./modules/caching"

  project_name                   = var.project_name
  environment                    = var.environment
  vpc_id                         = module.networking.vpc_id
  elasticache_subnet_group_name  = module.networking.elasticache_subnet_group_name
  elasticache_security_group_id  = module.networking.elasticache_security_group_id
  private_subnet_ids             = module.networking.private_subnet_ids
}

# Messaging Module
module "messaging" {
  source = "./modules/messaging"

  project_name = var.project_name
  environment  = var.environment
}

# Compute Module
module "compute" {
  source = "./modules/compute"

  project_name                 = var.project_name
  environment                  = var.environment
  vpc_id                       = module.networking.vpc_id
  private_subnet_ids           = module.networking.private_subnet_ids
  ec2_security_group_id        = module.networking.ec2_security_group_id
  ecs_task_security_group_id   = module.networking.ecs_task_security_group_id
  eks_node_security_group_id   = module.networking.eks_node_security_group_id
}

# Load Balancing Module
module "loadbalancing" {
  source = "./modules/loadbalancing"

  project_name                 = var.project_name
  environment                  = var.environment
  vpc_id                       = module.networking.vpc_id
  public_subnet_ids            = module.networking.public_subnet_ids
  private_subnet_ids           = module.networking.private_subnet_ids
  alb_security_group_id        = module.networking.alb_security_group_id
  ecs_task_security_group_id   = module.networking.ecs_task_security_group_id
  eks_node_security_group_id   = module.networking.eks_node_security_group_id
  ec2_security_group_id        = module.networking.ec2_security_group_id
  ec2_autoscaling_group_name   = module.compute.ec2_autoscaling_group_name
}

# Serverless Module
module "serverless" {
  source = "./modules/serverless"

  project_name                   = var.project_name
  environment                    = var.environment
  vpc_id                         = module.networking.vpc_id
  private_subnet_ids             = module.networking.private_subnet_ids
  payment_processing_queue_arn   = module.messaging.payment_processing_queue_arn
  payment_processing_queue_url   = module.messaging.payment_processing_queue_url
  analytics_events_stream_arn    = module.messaging.analytics_events_stream_arn
  analytics_events_stream_name   = module.messaging.analytics_events_stream_name
  alb_arn                        = module.loadbalancing.alb_arn
  alb_dns_name                   = module.loadbalancing.alb_dns_name
  nlb_arn                        = module.loadbalancing.nlb_arn
  alb_listener_arn               = module.loadbalancing.alb_listener_arn
}

# Frontend Module
module "frontend" {
  source = "./modules/frontend"

  project_name     = var.project_name
  environment      = var.environment
  alb_dns_name     = module.loadbalancing.alb_dns_name
  api_gateway_url  = module.serverless.api_gateway_url
}
