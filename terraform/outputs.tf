output "load_balancer_dns" {
  value = module.alb.lb_dns
}

output "product_tg" {
  value = module.target_group.product_tg_arn
}

output "cart_tg" {
  value = module.target_group.cart_tg_arn
}

output "cca_tg" {
  value = module.target_group.cca_tg_arn
}

output "rabbitmq_endpoint" {
  value = module.rabbitmq.endpoint
}

output "cluster_name" {
  value = module.ecs_cluster.cluster_name
}

output "rabbitmq_nlb_dns" {
  value = module.rabbitmq.nlb_dns_name
}