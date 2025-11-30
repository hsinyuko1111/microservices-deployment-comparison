module "network" {
  source = "./modules/network"

  vpc_cidr           = "10.0.0.0/16"
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
}

module "alb" {
  source = "./modules/alb"

  vpc_id = module.network.vpc_id
  subnets = module.network.public_subnets
  sg_id   = module.network.alb_sg_id
  product_tg_arn = module.target_group.product_tg_arn
  cart_tg_arn    = module.target_group.cart_tg_arn
  cca_tg_arn     = module.target_group.cca_tg_arn
}

module "target_group" {
  source = "./modules/target-group"

  vpc_id = module.network.vpc_id
}

module "ecr" {
  source = "./modules/ecr"

  repositories = [
    "product-service",
    "product-service-bad",
    "shopping-cart-service",
    "credit-card-authorizer",
    "warehouse-consumer"
  ]
}

data "aws_iam_role" "ecs_execution" {
  name = "LabRole"
}

module "logging" {
  source          = "./modules/logging"
}

module "ecs_cluster" {
  source = "./modules/ecs-cluster"

  cluster_name = "microservices-cluster"
}

module "rabbitmq" {
  source       = "./modules/rabbitmq"
  subnets      = module.network.public_subnets
  vpc_id       = module.network.vpc_id
  cluster_name = module.ecs_cluster.cluster_name

  depends_on = [module.ecs_cluster]
}

module "ecs" {
  source = "./modules/ecs"

  cluster_name       = module.ecs_cluster.cluster_name
  subnets            = module.network.public_subnets
  execution_role_arn = data.aws_iam_role.ecs_execution.arn
  task_role_arn      = data.aws_iam_role.ecs_execution.arn
  log_group_name     = module.logging.log_group_name
  region             = var.region
  alb_dns            = module.alb.dns_name
  rabbitmq_url       = module.rabbitmq.endpoint
  ecs_sg_id          = module.network.ecs_tasks_sg_id

  services = {
    product = {
      image        = "${module.ecr.repo_urls["product-service"]}:latest"
      tg_arn       = module.target_group.product_tg_arn
      container_port = 8080
    }
    product_bad = {
      image        = "${module.ecr.repo_urls["product-service-bad"]}:latest"
      tg_arn       = module.target_group.product_tg_arn
      container_port = 8080
    }
    shopping_cart = {
      image        = "${module.ecr.repo_urls["shopping-cart-service"]}:latest"
      tg_arn       = module.target_group.cart_tg_arn
      container_port = 8081
    }
    cca = {
      image        = "${module.ecr.repo_urls["credit-card-authorizer"]}:latest"
      tg_arn       = module.target_group.cca_tg_arn
      container_port = 8082
    }
    warehouse = {
      image        = "${module.ecr.repo_urls["warehouse-consumer"]}:latest"
      tg_arn       = null
      container_port = 0
    }
  }

  depends_on = [module.rabbitmq]
}

# ---- BUILD DOCKER IMAGES FOR ALL SERVICES ----
locals {
  services = [
    "product-service",
    "product-service-bad",
    "shopping-cart-service",
    "credit-card-authorizer",
    "warehouse-consumer"
  ]
}

# Build Docker images
resource "docker_image" "services" {
  for_each = toset(local.services)

  name = "${module.ecr.repo_urls[each.key]}:latest"

  build {
    # terraform/ → services/<service>/
    context = "../services/${each.key}"
  }
}

# Push to ECR
resource "docker_registry_image" "services" {
  for_each = docker_image.services

  name = each.value.name
}