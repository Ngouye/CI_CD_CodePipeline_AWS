# Service ECS Fargate piloté par CodeDeploy (deployment controller CODE_DEPLOY).

resource "aws_ecs_cluster" "this" {
  name = local.name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${local.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.this.arn
}

resource "aws_security_group" "ecs" {
  name        = "${local.name}-ecs"
  description = "Taches ECS : entree depuis l'ALB uniquement"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${local.name}-ecs" }
}

resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb" {
  security_group_id            = aws_security_group.ecs.id
  description                  = "Depuis l'ALB"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = local.container_port
  to_port                      = local.container_port
}

#tfsec:ignore:aws-ec2-no-public-egress-sgr HTTPS sortant via NAT (ECR, CloudWatch Logs).
resource "aws_vpc_security_group_egress_rule" "ecs_https" {
  security_group_id = aws_security_group.ecs.id
  description       = "HTTPS sortant (ECR, CloudWatch Logs)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# Task definition initiale : un serveur HTTP minimal qui répond 200 en attendant
# que le pipeline enregistre la première vraie révision (même famille).
resource "aws_ecs_task_definition" "bootstrap" {
  family                   = "${local.name}-app"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name                   = local.container_name
    image                  = var.bootstrap_image
    essential              = true
    user                   = "node"
    readonlyRootFilesystem = true
    command = [
      "node", "-e",
      "require('http').createServer((q, s) => s.end('En attente du premier deploiement CodePipeline')).listen(${local.container_port})",
    ]
    portMappings = [{ containerPort = local.container_port, protocol = "tcp" }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.ecs.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "bootstrap"
      }
    }
  }])
}

resource "aws_ecs_service" "app" {
  name                              = "${local.name}-app"
  cluster                           = aws_ecs_cluster.this.id
  task_definition                   = aws_ecs_task_definition.bootstrap.arn
  desired_count                     = var.ecs_desired_count
  launch_type                       = "FARGATE"
  platform_version                  = "LATEST"
  health_check_grace_period_seconds = 30
  propagate_tags                    = "SERVICE"

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs["blue"].arn
    container_name   = local.container_name
    container_port   = local.container_port
  }

  # Après chaque déploiement, CodeDeploy change la task definition et le target group actif.
  lifecycle {
    ignore_changes = [task_definition, load_balancer, desired_count]
  }

  depends_on = [aws_lb_listener.ecs_prod, aws_lb_listener.ecs_test]
}
