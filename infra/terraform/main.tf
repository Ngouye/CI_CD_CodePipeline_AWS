data "aws_caller_identity" "current" {}

# Zones épinglées : le réseau reste identique même si AWS ajoute une AZ à la région.
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "zone-name"
    values = [for suffix in ["a", "b"] : "${var.aws_region}${suffix}"]
  }
}

locals {
  name       = "${var.project_name}-${var.environment}"
  short_name = substr(local.name, 0, 20) # ALB, target groups et connexion : 32 caractères max
  account_id = data.aws_caller_identity.current.account_id
  azs        = slice(data.aws_availability_zones.available.names, 0, 2)

  container_name = "app"
  container_port = 8080

  test_listener_cidrs = length(var.test_listener_allowed_cidrs) > 0 ? var.test_listener_allowed_cidrs : [var.vpc_cidr]
}
