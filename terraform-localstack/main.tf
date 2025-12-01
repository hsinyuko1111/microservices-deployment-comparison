# terraform-localstack/main.tf
# LocalStack deployment - mirrors AWS infrastructure locally
#
# Usage:
#   cd terraform-localstack
#   terraform init
#   terraform apply

# =============================================================================
# NETWORKING
# =============================================================================

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "localstack-vpc" }
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = { Name = "localstack-public-1" }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = { Name = "localstack-public-2" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "localstack-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "localstack-public-rt" }
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# =============================================================================
# SECURITY GROUPS
# =============================================================================

resource "aws_security_group" "alb" {
  name        = "localstack-alb-sg"
  description = "ALB security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "localstack-alb-sg" }
}

resource "aws_security_group" "ecs" {
  name        = "localstack-ecs-sg"
  description = "ECS tasks security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "localstack-ecs-sg" }
}

# =============================================================================
# IAM ROLES
# =============================================================================

resource "aws_iam_role" "ecs_execution" {
  name = "localstack-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# =============================================================================
# ECR REPOSITORIES
# =============================================================================

resource "aws_ecr_repository" "services" {
  for_each = toset([
    "product-service",
    "product-service-bad",
    "shopping-cart-service",
    "credit-card-authorizer",
    "warehouse-consumer"
  ])

  name         = each.key
  force_delete = true
}

# =============================================================================
# ECS CLUSTER
# =============================================================================

resource "aws_ecs_cluster" "main" {
  name = "localstack-cluster"
}

# =============================================================================
# CLOUDWATCH LOG GROUP
# =============================================================================

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/localstack"
  retention_in_days = 1
}

# =============================================================================
# APPLICATION LOAD BALANCER
# =============================================================================

resource "aws_lb" "main" {
  name               = "localstack-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }
}

# =============================================================================
# TARGET GROUPS
# =============================================================================

resource "aws_lb_target_group" "product" {
  name        = "product-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/product"
    matcher             = "200-499"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    interval            = 30
    timeout             = 10
  }
}

resource "aws_lb_target_group" "cart" {
  name        = "cart-tg"
  port        = 8081
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/shopping-cart"
    matcher             = "200-499"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    interval            = 30
    timeout             = 10
  }
}

resource "aws_lb_target_group" "cca" {
  name        = "cca-tg"
  port        = 8082
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/credit-card-authorizer"
    matcher             = "200-499"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    interval            = 30
    timeout             = 10
  }
}

# =============================================================================
# ALB LISTENER RULES
# =============================================================================

resource "aws_lb_listener_rule" "product" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.product.arn
  }

  condition {
    path_pattern { values = ["/product*"] }
  }
}

resource "aws_lb_listener_rule" "cart" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.cart.arn
  }

  condition {
    path_pattern { values = ["/shopping-cart*", "/shopping-carts*"] }
  }
}

resource "aws_lb_listener_rule" "cca" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 30

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.cca.arn
  }

  condition {
    path_pattern { values = ["/credit-card-authorizer*"] }
  }
}

# =============================================================================
# RABBITMQ (Network Load Balancer + ECS Service)
# =============================================================================

resource "aws_lb" "rabbitmq" {
  name               = "rabbitmq-nlb"
  load_balancer_type = "network"
  internal           = true
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

resource "aws_lb_target_group" "rabbitmq" {
  name        = "rabbitmq-tg"
  port        = 5672
  protocol    = "TCP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    protocol = "TCP"
    port     = "traffic-port"
  }
}

resource "aws_lb_listener" "rabbitmq" {
  load_balancer_arn = aws_lb.rabbitmq.arn
  port              = 5672
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rabbitmq.arn
  }
}

resource "aws_ecs_task_definition" "rabbitmq" {
  family                   = "rabbitmq"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_execution.arn

  container_definitions = jsonencode([{
    name      = "rabbitmq"
    image     = "rabbitmq:3-management"
    essential = true
    portMappings = [
      { containerPort = 5672, protocol = "tcp" },
      { containerPort = 15672, protocol = "tcp" }
    ]
    environment = [
      { name = "RABBITMQ_DEFAULT_USER", value = "guest" },
      { name = "RABBITMQ_DEFAULT_PASS", value = "guest" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.ecs.name
        awslogs-region        = "us-east-1"
        awslogs-stream-prefix = "rabbitmq"
      }
    }
  }])
}

resource "aws_ecs_service" "rabbitmq" {
  name            = "rabbitmq"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.rabbitmq.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public_1.id, aws_subnet.public_2.id]
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.rabbitmq.arn
    container_name   = "rabbitmq"
    container_port   = 5672
  }
}

# =============================================================================
# ECS TASK DEFINITIONS
# =============================================================================

resource "aws_ecs_task_definition" "product" {
  family                   = "product-service"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_execution.arn

  container_definitions = jsonencode([{
    name      = "product-service"
    image     = "${aws_ecr_repository.services["product-service"].repository_url}:latest"
    essential = true
    portMappings = [{ containerPort = 8080 }]
    environment = [{ name = "PORT", value = "8080" }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.ecs.name
        awslogs-region        = "us-east-1"
        awslogs-stream-prefix = "product"
      }
    }
  }])
}

resource "aws_ecs_task_definition" "product_bad" {
  family                   = "product-service-bad"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_execution.arn

  container_definitions = jsonencode([{
    name      = "product-service-bad"
    image     = "${aws_ecr_repository.services["product-service-bad"].repository_url}:latest"
    essential = true
    portMappings = [{ containerPort = 8080 }]
    environment = [{ name = "PORT", value = "8080" }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.ecs.name
        awslogs-region        = "us-east-1"
        awslogs-stream-prefix = "product-bad"
      }
    }
  }])
}

resource "aws_ecs_task_definition" "shopping_cart" {
  family                   = "shopping-cart-service"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_execution.arn

  container_definitions = jsonencode([{
    name      = "shopping-cart-service"
    image     = "${aws_ecr_repository.services["shopping-cart-service"].repository_url}:latest"
    essential = true
    portMappings = [{ containerPort = 8081 }]
    environment = [
      { name = "PORT", value = "8081" },
      { name = "CCA_SERVICE_URL", value = "http://${aws_lb.main.dns_name}" },
      { name = "RABBITMQ_URL", value = "amqp://guest:guest@${aws_lb.rabbitmq.dns_name}:5672/" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.ecs.name
        awslogs-region        = "us-east-1"
        awslogs-stream-prefix = "shopping-cart"
      }
    }
  }])
}

resource "aws_ecs_task_definition" "cca" {
  family                   = "credit-card-authorizer"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_execution.arn

  container_definitions = jsonencode([{
    name      = "credit-card-authorizer"
    image     = "${aws_ecr_repository.services["credit-card-authorizer"].repository_url}:latest"
    essential = true
    portMappings = [{ containerPort = 8082 }]
    environment = [{ name = "PORT", value = "8082" }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.ecs.name
        awslogs-region        = "us-east-1"
        awslogs-stream-prefix = "cca"
      }
    }
  }])
}

resource "aws_ecs_task_definition" "warehouse" {
  family                   = "warehouse-consumer"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_execution.arn

  container_definitions = jsonencode([{
    name      = "warehouse-consumer"
    image     = "${aws_ecr_repository.services["warehouse-consumer"].repository_url}:latest"
    essential = true
    environment = [
      { name = "RABBITMQ_URL", value = "amqp://guest:guest@${aws_lb.rabbitmq.dns_name}:5672/" },
      { name = "RABBITMQ_QUEUE", value = "warehouse_orders" },
      { name = "NUM_WORKERS", value = "5" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.ecs.name
        awslogs-region        = "us-east-1"
        awslogs-stream-prefix = "warehouse"
      }
    }
  }])
}

# =============================================================================
# ECS SERVICES
# =============================================================================

resource "aws_ecs_service" "product" {
  name            = "product-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.product.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public_1.id, aws_subnet.public_2.id]
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.product.arn
    container_name   = "product-service"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener_rule.product]
}

resource "aws_ecs_service" "product_bad" {
  name            = "product-service-bad"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.product_bad.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public_1.id, aws_subnet.public_2.id]
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.product.arn
    container_name   = "product-service-bad"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener_rule.product]
}

resource "aws_ecs_service" "shopping_cart" {
  name            = "shopping-cart-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.shopping_cart.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public_1.id, aws_subnet.public_2.id]
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.cart.arn
    container_name   = "shopping-cart-service"
    container_port   = 8081
  }

  depends_on = [aws_lb_listener_rule.cart, aws_ecs_service.rabbitmq]
}

resource "aws_ecs_service" "cca" {
  name            = "cca-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.cca.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public_1.id, aws_subnet.public_2.id]
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.cca.arn
    container_name   = "credit-card-authorizer"
    container_port   = 8082
  }

  depends_on = [aws_lb_listener_rule.cca]
}

resource "aws_ecs_service" "warehouse" {
  name            = "warehouse-consumer"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.warehouse.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public_1.id, aws_subnet.public_2.id]
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  depends_on = [aws_ecs_service.rabbitmq]
}