# Un projet CodeBuild par étape du pipeline ; les buildspecs vivent dans le dépôt.

locals {
  codebuild_projects = {
    secrets = {
      description = "Detection de secrets : Gitleaks, TruffleHog"
      buildspec   = "buildspecs/secrets.yml"
      compute     = "BUILD_GENERAL1_SMALL"
      privileged  = false
    }
    sast = {
      description = "SAST : Semgrep, Bearer, SonarQube"
      buildspec   = "buildspecs/sast.yml"
      compute     = "BUILD_GENERAL1_MEDIUM"
      privileged  = false
    }
    iac = {
      description = "Scan IaC : Checkov, tfsec"
      buildspec   = "buildspecs/iac.yml"
      compute     = "BUILD_GENERAL1_SMALL"
      privileged  = false
    }
    build = {
      description = "Tests, SCA Trivy, build Docker, scan image Dockle + Trivy, push ECR"
      buildspec   = "buildspecs/build.yml"
      compute     = "BUILD_GENERAL1_MEDIUM"
      privileged  = true
    }
    dast = {
      description = "DAST : OWASP ZAP sur les environnements deployes"
      buildspec   = "buildspecs/dast.yml"
      compute     = "BUILD_GENERAL1_SMALL"
      privileged  = true
    }
  }

  codebuild_env = {
    build = {
      ECR_REPOSITORY_URI = aws_ecr_repository.app.repository_url
      TASK_FAMILY        = aws_ecs_task_definition.bootstrap.family
      CONTAINER_NAME     = local.container_name
      EXECUTION_ROLE_ARN = aws_iam_role.ecs_execution.arn
      TASK_ROLE_ARN      = aws_iam_role.ecs_task.arn
      LOG_GROUP          = aws_cloudwatch_log_group.ecs.name
    }
    sast = {
      SONAR_HOST_URL     = var.sonar_host_url
      SONAR_ORGANIZATION = var.sonar_organization
      SONAR_PROJECT_KEY  = var.sonar_project_key
    }
    dast = {
      TARGET_URLS = "http://${aws_lb.ecs.dns_name} http://${aws_lb.ec2.dns_name}"
    }
  }
}

resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/aws/codebuild/${local.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.this.arn
}

resource "aws_codebuild_project" "this" {
  for_each = local.codebuild_projects
  #checkov:skip=CKV_AWS_316:Docker-in-Docker requis pour construire/scanner l'image (build) et lancer ZAP (dast).

  name           = "${local.name}-${each.key}"
  description    = each.value.description
  service_role   = aws_iam_role.codebuild.arn
  build_timeout  = 30
  queued_timeout = 60
  encryption_key = aws_kms_key.this.arn

  source {
    type      = "CODEPIPELINE"
    buildspec = each.value.buildspec
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = each.value.compute
    image                       = var.codebuild_image
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = each.value.privileged

    environment_variable {
      name  = "REPORTS_BUCKET"
      value = aws_s3_bucket.artifacts.bucket
    }

    dynamic "environment_variable" {
      for_each = lookup(local.codebuild_env, each.key, {})

      content {
        name  = environment_variable.key
        value = environment_variable.value
      }
    }

    # Token Sonar injecté depuis Secrets Manager, jamais en clair dans Terraform.
    dynamic "environment_variable" {
      for_each = each.key == "sast" && var.sonar_token_secret_arn != "" ? [var.sonar_token_secret_arn] : []

      content {
        name  = "SONAR_TOKEN"
        type  = "SECRETS_MANAGER"
        value = environment_variable.value
      }
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codebuild.name
      stream_name = each.key
    }
  }
}
