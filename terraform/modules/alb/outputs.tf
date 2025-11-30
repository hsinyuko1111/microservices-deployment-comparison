output "lb_arn" {
  value = aws_lb.app.arn
}

output "listener_arn" {
  value = aws_lb_listener.http.arn
}

output "lb_dns" {
  value = aws_lb.app.dns_name
}

output "dns_name" {
  value = aws_lb.app.dns_name
}