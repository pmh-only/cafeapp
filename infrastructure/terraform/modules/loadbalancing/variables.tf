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

variable "public_subnet_ids" {
  description = "List of public subnet IDs for ALB"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for NLB"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group ID for ALB"
  type        = string
}

variable "ecs_task_security_group_id" {
  description = "Security group ID for ECS tasks"
  type        = string
}

variable "eks_node_security_group_id" {
  description = "Security group ID for EKS nodes"
  type        = string
}

variable "ec2_security_group_id" {
  description = "Security group ID for EC2 instances"
  type        = string
}

variable "ec2_autoscaling_group_name" {
  description = "EC2 Auto Scaling Group name for NLB target"
  type        = string
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for load balancers"
  type        = bool
  default     = false
}

variable "enable_access_logs" {
  description = "Enable access logs for load balancers"
  type        = bool
  default     = false
}
