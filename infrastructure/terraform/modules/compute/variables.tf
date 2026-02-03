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

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "ec2_security_group_id" {
  description = "Security group ID for EC2 instances"
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

variable "ec2_instance_type" {
  description = "EC2 instance type for loyalty service"
  type        = string
  default     = "t3.large"
}

variable "ec2_min_size" {
  description = "Minimum size of EC2 Auto Scaling Group"
  type        = number
  default     = 2
}

variable "ec2_max_size" {
  description = "Maximum size of EC2 Auto Scaling Group"
  type        = number
  default     = 10
}

variable "ec2_desired_capacity" {
  description = "Desired capacity of EC2 Auto Scaling Group"
  type        = number
  default     = 2
}

variable "eks_node_instance_types" {
  description = "Instance types for EKS managed node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "eks_node_min_size" {
  description = "Minimum size of EKS node group"
  type        = number
  default     = 2
}

variable "eks_node_max_size" {
  description = "Maximum size of EKS node group"
  type        = number
  default     = 10
}

variable "eks_node_desired_size" {
  description = "Desired size of EKS node group"
  type        = number
  default     = 3
}
