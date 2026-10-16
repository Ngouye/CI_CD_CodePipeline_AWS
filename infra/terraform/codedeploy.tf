# Déploiements blue/green avec rollback automatique (échec ou alarme 5xx).

# --- Alarmes de rollback --------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  for_each = {
    ecs = aws_lb.ecs.arn_suffix
    ec2 = aws_lb.ec2.arn_suffix
  }

  alarm_name          = "${local.name}-${each.key}-target-5xx"
  alarm_description   = "Erreurs 5xx applicatives : déclenche le rollback CodeDeploy"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = { LoadBalancer = each.value }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
}

# --- ECS (Fargate) ------------------------------------------------------------------

resource "aws_codedeploy_app" "ecs" {
  name             = "${local.name}-ecs"
  compute_platform = "ECS"
}

resource "aws_codedeploy_deployment_group" "ecs" {
  app_name               = aws_codedeploy_app.ecs.name
  deployment_group_name  = "${local.name}-ecs"
  service_role_arn       = aws_iam_role.codedeploy.arn
  deployment_config_name = var.ecs_deployment_config

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = var.blue_termination_wait_minutes
    }
  }

  ecs_service {
    cluster_name = aws_ecs_cluster.this.name
    service_name = aws_ecs_service.app.name
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [aws_lb_listener.ecs_prod.arn]
      }

      test_traffic_route {
        listener_arns = [aws_lb_listener.ecs_test.arn]
      }

      target_group {
        name = aws_lb_target_group.ecs["blue"].name
      }

      target_group {
        name = aws_lb_target_group.ecs["green"].name
      }
    }
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }

  alarm_configuration {
    enabled = true
    alarms  = [aws_cloudwatch_metric_alarm.target_5xx["ecs"].alarm_name]
  }
}

# --- EC2 (Auto Scaling) ---------------------------------------------------------------

resource "aws_codedeploy_app" "ec2" {
  name             = "${local.name}-ec2"
  compute_platform = "Server"
}

resource "aws_codedeploy_deployment_group" "ec2" {
  app_name               = aws_codedeploy_app.ec2.name
  deployment_group_name  = "${local.name}-ec2"
  service_role_arn       = aws_iam_role.codedeploy.arn
  deployment_config_name = "CodeDeployDefault.AllAtOnce"
  autoscaling_groups     = [aws_autoscaling_group.app.name]

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    green_fleet_provisioning_option {
      action = "COPY_AUTO_SCALING_GROUP"
    }

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = var.blue_termination_wait_minutes
    }
  }

  load_balancer_info {
    target_group_info {
      name = aws_lb_target_group.ec2.name
    }
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }

  alarm_configuration {
    enabled = true
    alarms  = [aws_cloudwatch_metric_alarm.target_5xx["ec2"].alarm_name]
  }

  # CodeDeploy remplace l'ASG par sa copie "green" à chaque déploiement.
  lifecycle {
    ignore_changes = [autoscaling_groups]
  }

  depends_on = [aws_iam_role_policy_attachment.codedeploy]
}
