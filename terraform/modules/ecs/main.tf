data "aws_ecs_cluster" "main" {
  cluster_name = var.cluster_name
}

variable "ecs_sg_id" {
  type = string
}

resource "aws_ecs_task_definition" "service" {
  for_each = var.services

  family                = "task-${each.key}"
  network_mode          = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                   = 256
  memory                = 512

  execution_role_arn = var.execution_role_arn

  container_definitions = jsonencode([
    {
      name      = each.key
      image     = each.value.image
      essential = true

      portMappings = each.value.container_port == 0 ? [] : [
        {
          containerPort = each.value.container_port
        }
      ]

      environment = concat(
        [
          {
            name  = "CCA_SERVICE_URL"
            value = "http://${var.alb_dns}"
          },
          {
            name  = "RABBITMQ_URL"
            value = var.rabbitmq_url
          }
        ],
        each.value.container_port != 0 ? [
          {
            name  = "PORT"
            value = tostring(each.value.container_port)
          }
        ] : []
      )

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-region        = var.region
          awslogs-group         = var.log_group_name
          awslogs-stream-prefix = each.key
        }
      }
    }
  ])
}

resource "aws_ecs_service" "service" {
  for_each = var.services

  cluster = data.aws_ecs_cluster.main.arn
  name    = "svc-${each.key}"

  task_definition = aws_ecs_task_definition.service[each.key].arn

  desired_count = each.key == "warehouse" ? 1 : 2

  launch_type = "FARGATE"

  network_configuration {
    subnets         = var.subnets
    assign_public_ip = true
    security_groups  = [var.ecs_sg_id]
  }

  dynamic "load_balancer" {
    for_each = each.value.tg_arn == null ? [] : [1]

    content {
      target_group_arn = each.value.tg_arn
      container_name   = each.key
      container_port   = each.value.container_port
    }
  }
}