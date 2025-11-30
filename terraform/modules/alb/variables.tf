variable "vpc_id" {
  type        = string
  description = "VPC ID where ALB is deployed"
}

variable "subnets" {
  type        = list(string)
  description = "List of public subnets for ALB"
}

# Optional: target groups for listener rules
variable "product_tg_arn" {
  type        = string
  description = "Target group ARN for Product Service"
  default     = null
}

variable "cart_tg_arn" {
  type        = string
  description = "Target group ARN for Shopping Cart Service"
  default     = null
}

variable "cca_tg_arn" {
  type        = string
  description = "Target group ARN for Credit Card Authorizer"
  default     = null
}

variable "sg_id" {
  type        = string
  description = "Security group ID for ALB"
}