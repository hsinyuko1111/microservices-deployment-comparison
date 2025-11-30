variable "cluster_name" {
  type = string
}

variable "subnets" {
  type = list(string)
}

variable "task_role_arn" {
  type = string
}

variable "execution_role_arn" {
  type = string
}

variable "services" {
  type = map(object({
    image          = string
    container_port = number
    tg_arn         = string
  }))
}

variable "log_group_name" {
  type = string
}

variable "region" {
  type        = string
  description = "AWS region for CloudWatch Logs"
}

variable "alb_dns" {
  type = string
}

variable "rabbitmq_url" {
  type        = string
  description = "RabbitMQ connection URL"
}