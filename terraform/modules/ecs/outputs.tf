output "service_arns" {
  value = {
    for name, svc in aws_ecs_service.service :
    name => svc.id
  }
}