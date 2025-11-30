resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/microservices"
  retention_in_days = 30
}