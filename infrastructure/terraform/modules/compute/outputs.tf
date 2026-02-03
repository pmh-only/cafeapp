output "ecs_cluster_id" {
  description = "ECS cluster ID"
  value       = aws_ecs_cluster.main.id
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "ecs_cluster_arn" {
  description = "ECS cluster ARN"
  value       = aws_ecs_cluster.main.arn
}

output "ecs_task_execution_role_arn" {
  description = "ECS task execution role ARN"
  value       = aws_iam_role.ecs_task_execution.arn
}

output "ecs_task_role_arn" {
  description = "ECS task role ARN"
  value       = aws_iam_role.ecs_task.arn
}

output "eks_cluster_id" {
  description = "EKS cluster ID"
  value       = aws_eks_cluster.main.id
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_certificate_authority_data" {
  description = "EKS cluster certificate authority data"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "eks_oidc_provider_arn" {
  description = "EKS OIDC provider ARN"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "eks_node_group_id" {
  description = "EKS node group ID"
  value       = aws_eks_node_group.main.id
}

output "ec2_autoscaling_group_name" {
  description = "EC2 Auto Scaling Group name"
  value       = aws_autoscaling_group.loyalty_service.name
}

output "ec2_autoscaling_group_arn" {
  description = "EC2 Auto Scaling Group ARN"
  value       = aws_autoscaling_group.loyalty_service.arn
}

output "ec2_iam_role_name" {
  description = "EC2 IAM role name"
  value       = aws_iam_role.ec2.name
}

output "ec2_launch_template_id" {
  description = "EC2 launch template ID"
  value       = aws_launch_template.loyalty_service.id
}
