resource "aws_ecr_repository" "repos" {
  for_each = toset(var.repositories)

  name = each.key
}