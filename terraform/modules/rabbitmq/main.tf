variable "subnets" {
  type = list(string)
}

variable "vpc_id" {
  type = string
}

variable "cluster_name" {
  type = string
}

data "aws_ecs_cluster" "cluster" {
  cluster_name = var.cluster_name
}

data "aws_region" "current" {}

data "aws_iam_role" "ecs_execution_role" {
  name = "LabRole"
}

resource "aws_security_group" "rabbitmq" {
  name_prefix = "rabbitmq-"
  description = "Security group for RabbitMQ"
  vpc_id      = var.vpc_id

  ingress {
    description = "AMQP"
    from_port   = 5672
    to_port     = 5672
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Management"
    from_port   = 15672
    to_port     = 15672
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "rabbitmq" {
  name              = "/ecs/rabbitmq"
  retention_in_days = 7
}

# Network Load Balancer
resource "aws_lb" "rabbitmq" {
  name               = "rabbitmq-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = var.subnets

  enable_cross_zone_load_balancing = true
}

# Target Group
resource "aws_lb_target_group" "rabbitmq" {
  name        = "rabbitmq-tg"
  port        = 5672
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
  }

  deregistration_delay = 30
}

# Listener
resource "aws_lb_listener" "rabbitmq" {
  load_balancer_arn = aws_lb.rabbitmq.arn
  port              = 5672
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rabbitmq.arn
  }
}

# Task Definition
resource "aws_ecs_task_definition" "rabbitmq" {
  family                   = "rabbitmq"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = data.aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "rabbitmq"
      image     = "rabbitmq:3-management"
      essential = true

      environment = [
        {
          name  = "RABBITMQ_ERLANG_COOKIE"
          value = "SWQOKODSQALRPCLNMEQG"
        },
        {
          name  = "RABBITMQ_DEFAULT_USER"
          value = "guest"
        },
        {
          name  = "RABBITMQ_DEFAULT_PASS"
          value = "guest"
        }
      ]

      user = "rabbitmq" 

      portMappings = [
        { 
          containerPort = 5672
          protocol      = "tcp"
        },
        { 
          containerPort = 15672
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.rabbitmq.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "rabbitmq"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "rabbitmq-diagnostics -q ping"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])
}

# ECS Service
resource "aws_ecs_service" "rabbitmq" {
  name            = "rabbitmq"
  cluster         = data.aws_ecs_cluster.cluster.arn
  task_definition = aws_ecs_task_definition.rabbitmq.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = var.subnets
    assign_public_ip = true
    security_groups  = [aws_security_group.rabbitmq.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.rabbitmq.arn
    container_name   = "rabbitmq"
    container_port   = 5672
  }

  health_check_grace_period_seconds = 60

  depends_on = [aws_lb_listener.rabbitmq]
}

output "endpoint" {
  value       = "amqp://guest:guest@${aws_lb.rabbitmq.dns_name}:5672/"
  description = "RabbitMQ connection endpoint"
}

output "nlb_dns_name" {
  value       = aws_lb.rabbitmq.dns_name
  description = "RabbitMQ NLB DNS name"
}

output "mgmt_url" {
  value       = "http://${aws_lb.rabbitmq.dns_name}:15672"
  description = "RabbitMQ management URL"
}