# Application Load Balancer
resource "aws_lb" "application" {
  name               = "${var.project_name}-alb-${var.environment}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = var.enable_deletion_protection
  enable_http2              = true
  enable_cross_zone_load_balancing = true

  tags = {
    Name        = "${var.project_name}-alb-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# ALB Listener - HTTP (Port 80)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.application.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "CloudCafe API - No route matched"
      status_code  = "404"
    }
  }

  tags = {
    Name        = "${var.project_name}-alb-listener-http-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# Target Group - Order Service (ECS)
resource "aws_lb_target_group" "order_service" {
  name        = "${var.project_name}-order-tg-${var.environment}"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = {
    Name        = "${var.project_name}-order-tg-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
    Service     = "order"
  }
}

# Target Group - Menu Service (EKS)
resource "aws_lb_target_group" "menu_service" {
  name        = "${var.project_name}-menu-tg-${var.environment}"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = {
    Name        = "${var.project_name}-menu-tg-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
    Service     = "menu"
  }
}

# Target Group - Inventory Service (EKS)
resource "aws_lb_target_group" "inventory_service" {
  name        = "${var.project_name}-inventory-tg-${var.environment}"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = {
    Name        = "${var.project_name}-inventory-tg-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
    Service     = "inventory"
  }
}

# ALB Listener Rule - Order Service
resource "aws_lb_listener_rule" "order_service" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.order_service.arn
  }

  condition {
    path_pattern {
      values = ["/api/orders*", "/orders*"]
    }
  }

  tags = {
    Name        = "${var.project_name}-order-rule-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# ALB Listener Rule - Menu Service
resource "aws_lb_listener_rule" "menu_service" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.menu_service.arn
  }

  condition {
    path_pattern {
      values = ["/api/menu*", "/menu*"]
    }
  }

  tags = {
    Name        = "${var.project_name}-menu-rule-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# ALB Listener Rule - Inventory Service
resource "aws_lb_listener_rule" "inventory_service" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 300

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.inventory_service.arn
  }

  condition {
    path_pattern {
      values = ["/api/inventory*", "/inventory*"]
    }
  }

  tags = {
    Name        = "${var.project_name}-inventory-rule-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# Network Load Balancer (Internal)
resource "aws_lb" "network" {
  name               = "${var.project_name}-nlb-${var.environment}"
  internal           = true
  load_balancer_type = "network"
  subnets            = var.private_subnet_ids

  enable_deletion_protection       = var.enable_deletion_protection
  enable_cross_zone_load_balancing = true

  tags = {
    Name        = "${var.project_name}-nlb-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# NLB Target Group - Loyalty Service (EC2)
resource "aws_lb_target_group" "loyalty_service" {
  name        = "${var.project_name}-loyalty-tg-${var.environment}"
  port        = 8080
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
    port                = "8080"
    protocol            = "TCP"
  }

  deregistration_delay = 30

  tags = {
    Name        = "${var.project_name}-loyalty-tg-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
    Service     = "loyalty"
  }
}

# NLB Listener
resource "aws_lb_listener" "network" {
  load_balancer_arn = aws_lb.network.arn
  port              = "8080"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.loyalty_service.arn
  }

  tags = {
    Name        = "${var.project_name}-nlb-listener-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# Attach EC2 Auto Scaling Group to NLB Target Group
resource "aws_autoscaling_attachment" "loyalty_service" {
  autoscaling_group_name = var.ec2_autoscaling_group_name
  lb_target_group_arn    = aws_lb_target_group.loyalty_service.arn
}

# VPC Lattice Service Network
resource "aws_vpclattice_service_network" "main" {
  name      = "${var.project_name}-service-network-${var.environment}"
  auth_type = "NONE"

  tags = {
    Name        = "${var.project_name}-service-network-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# VPC Lattice Service Network VPC Association
resource "aws_vpclattice_service_network_vpc_association" "main" {
  vpc_identifier             = var.vpc_id
  service_network_identifier = aws_vpclattice_service_network.main.id
  security_group_ids         = [var.ecs_task_security_group_id, var.eks_node_security_group_id]

  tags = {
    Name        = "${var.project_name}-lattice-vpc-assoc-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# VPC Lattice Target Group - Order Service
resource "aws_vpclattice_target_group" "order_service" {
  name = "${var.project_name}-order-lattice-tg-${var.environment}"
  type = "IP"

  config {
    port             = 8080
    protocol         = "HTTP"
    vpc_identifier   = var.vpc_id
    protocol_version = "HTTP1"

    health_check {
      enabled                       = true
      health_check_interval_seconds = 30
      health_check_timeout_seconds  = 5
      healthy_threshold_count       = 2
      unhealthy_threshold_count     = 2
      path                          = "/health"
      protocol                      = "HTTP"
      protocol_version              = "HTTP1"
      matcher {
        value = "200"
      }
    }
  }

  tags = {
    Name        = "${var.project_name}-order-lattice-tg-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# VPC Lattice Service - Order Service
resource "aws_vpclattice_service" "order_service" {
  name      = "${var.project_name}-order-lattice-${var.environment}"
  auth_type = "NONE"

  tags = {
    Name        = "${var.project_name}-order-lattice-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# VPC Lattice Listener
resource "aws_vpclattice_listener" "order_service" {
  name               = "${var.project_name}-order-listener-${var.environment}"
  protocol           = "HTTP"
  service_identifier = aws_vpclattice_service.order_service.id

  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.order_service.id
        weight                  = 100
      }
    }
  }

  tags = {
    Name        = "${var.project_name}-order-listener-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# VPC Lattice Service Network Service Association
resource "aws_vpclattice_service_network_service_association" "order_service" {
  service_identifier         = aws_vpclattice_service.order_service.id
  service_network_identifier = aws_vpclattice_service_network.main.id

  tags = {
    Name        = "${var.project_name}-order-svc-assoc-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}
