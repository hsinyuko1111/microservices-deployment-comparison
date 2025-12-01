# terraform-localstack/outputs.tf

output "alb_dns_name" {
  value       = aws_lb.main.dns_name
  description = "ALB DNS name - use this for load testing"
}

output "alb_url" {
  value       = "http://${aws_lb.main.dns_name}"
  description = "Full ALB URL"
}

output "rabbitmq_url" {
  value       = "amqp://guest:guest@${aws_lb.rabbitmq.dns_name}:5672/"
  description = "RabbitMQ connection URL"
}

output "ecr_repositories" {
  value = {
    for name, repo in aws_ecr_repository.services : name => repo.repository_url
  }
  description = "ECR repository URLs for pushing images"
}

output "cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "vpc_id" {
  value = aws_vpc.main.id
}