resource "aws_lb" "app" {
  name               = "microservices-alb"
  load_balancer_type = "application"
  security_groups    = [var.sg_id]
  subnets            = var.subnets
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
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

# Product
resource "aws_lb_listener_rule" "product" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = var.product_tg_arn
  }

  condition {
    path_pattern {
      values = ["/product*"]
    }
  }
}

# Shopping Cart
resource "aws_lb_listener_rule" "cart" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = var.cart_tg_arn
  }

  condition {
    path_pattern {
      values = ["/shopping-cart*"]
    }
  }
}

# CCA
resource "aws_lb_listener_rule" "cca" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 30

  action {
    type             = "forward"
    target_group_arn = var.cca_tg_arn
  }

  condition {
    path_pattern {
      values = ["/credit-card-authorizer*"]
    }
  }
}