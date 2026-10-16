# Deux ALB publics : un pour ECS (listeners prod + test pour le blue/green),
# un pour la flotte EC2. Démo sans nom de domaine, donc HTTP uniquement :
# en production, ajouter un certificat ACM et un listener HTTPS.

resource "aws_security_group" "alb" {
  name        = "${local.name}-alb"
  description = "Trafic HTTP entrant vers les ALB"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${local.name}-alb" }
}

#tfsec:ignore:aws-ec2-no-public-ingress-sgr Application web publique exposée via l'ALB.
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP public"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "alb_test_listener" {
  for_each = toset(local.test_listener_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "Listener de test ECS blue/green"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 8080
  to_port           = 8080
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ecs" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Vers les taches ECS"
  referenced_security_group_id = aws_security_group.ecs.id
  ip_protocol                  = "tcp"
  from_port                    = local.container_port
  to_port                      = local.container_port
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ec2" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Vers les instances EC2"
  referenced_security_group_id = aws_security_group.ec2.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

# --- ALB ECS ------------------------------------------------------------------------

#tfsec:ignore:aws-elb-alb-not-public Point d'entrée public de l'application.
resource "aws_lb" "ecs" {
  name                       = "${local.short_name}-ecs"
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [aws_security_group.alb.id]
  subnets                    = aws_subnet.public[*].id
  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "ecs" {
  for_each = toset(["blue", "green"])

  name                 = "${local.short_name}-ecs-${each.key}"
  port                 = local.container_port
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = aws_vpc.this.id
  deregistration_delay = 30

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# CodeDeploy bascule les listeners entre blue et green : Terraform ne doit pas les réécrire.
#tfsec:ignore:aws-elb-http-not-used Démo sans domaine ni certificat ACM.
resource "aws_lb_listener" "ecs_prod" {
  load_balancer_arn = aws_lb.ecs.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs["blue"].arn
  }

  lifecycle {
    ignore_changes = [default_action]
  }
}

#tfsec:ignore:aws-elb-http-not-used Listener de test interne au blue/green.
resource "aws_lb_listener" "ecs_test" {
  load_balancer_arn = aws_lb.ecs.arn
  port              = 8080
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs["blue"].arn
  }

  lifecycle {
    ignore_changes = [default_action]
  }
}

# --- ALB EC2 ------------------------------------------------------------------------

#tfsec:ignore:aws-elb-alb-not-public Point d'entrée public de l'application.
resource "aws_lb" "ec2" {
  name                       = "${local.short_name}-ec2"
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [aws_security_group.alb.id]
  subnets                    = aws_subnet.public[*].id
  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "ec2" {
  name                 = "${local.short_name}-ec2"
  port                 = 80
  protocol             = "HTTP"
  target_type          = "instance"
  vpc_id               = aws_vpc.this.id
  deregistration_delay = 30

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

#tfsec:ignore:aws-elb-http-not-used Démo sans domaine ni certificat ACM.
resource "aws_lb_listener" "ec2" {
  load_balancer_arn = aws_lb.ec2.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ec2.arn
  }
}
