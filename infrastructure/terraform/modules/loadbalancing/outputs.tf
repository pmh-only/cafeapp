output "alb_id" {
  description = "Application Load Balancer ID"
  value       = aws_lb.application.id
}

output "alb_arn" {
  description = "Application Load Balancer ARN (for chaos scripts)"
  value       = aws_lb.application.arn
}

output "alb_dns_name" {
  description = "Application Load Balancer DNS name"
  value       = aws_lb.application.dns_name
}

output "alb_zone_id" {
  description = "Application Load Balancer hosted zone ID"
  value       = aws_lb.application.zone_id
}

output "alb_listener_arn" {
  description = "ALB HTTP listener ARN"
  value       = aws_lb_listener.http.arn
}

output "nlb_id" {
  description = "Network Load Balancer ID"
  value       = aws_lb.network.id
}

output "nlb_arn" {
  description = "Network Load Balancer ARN (for chaos scripts)"
  value       = aws_lb.network.arn
}

output "nlb_dns_name" {
  description = "Network Load Balancer DNS name"
  value       = aws_lb.network.dns_name
}

output "order_service_target_group_arn" {
  description = "Order service target group ARN"
  value       = aws_lb_target_group.order_service.arn
}

output "menu_service_target_group_arn" {
  description = "Menu service target group ARN"
  value       = aws_lb_target_group.menu_service.arn
}

output "inventory_service_target_group_arn" {
  description = "Inventory service target group ARN"
  value       = aws_lb_target_group.inventory_service.arn
}

output "loyalty_service_target_group_arn" {
  description = "Loyalty service target group ARN"
  value       = aws_lb_target_group.loyalty_service.arn
}

output "vpc_lattice_service_network_arn" {
  description = "VPC Lattice service network ARN (for chaos scripts)"
  value       = aws_vpclattice_service_network.main.arn
}

output "vpc_lattice_service_network_id" {
  description = "VPC Lattice service network ID"
  value       = aws_vpclattice_service_network.main.id
}

output "vpc_lattice_order_service_arn" {
  description = "VPC Lattice order service ARN"
  value       = aws_vpclattice_service.order_service.arn
}

output "vpc_lattice_order_service_dns" {
  description = "VPC Lattice order service DNS name"
  value       = aws_vpclattice_service.order_service.dns_entry[0].domain_name
}
