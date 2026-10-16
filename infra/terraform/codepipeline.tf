# Pipeline : Source -> Security-Scans -> Build -> [Approval] -> Deploy (blue/green) -> DAST

# Créée à l'état PENDING : la poignée de main GitHub se valide une fois dans la console.
resource "aws_codestarconnections_connection" "github" {
  name          = "${local.short_name}-github"
  provider_type = "GitHub"
}

locals {
  pipeline_env = [
    { name = "COMMIT_ID", value = "#{SourceVariables.CommitId}", type = "PLAINTEXT" },
    { name = "PIPELINE_EXECUTION_ID", value = "#{codepipeline.PipelineExecutionId}", type = "PLAINTEXT" },
  ]

  security_scans = {
    Secrets = "secrets"
    SAST    = "sast"
    IaC     = "iac"
  }
}

resource "aws_codepipeline" "this" {
  name          = local.name
  role_arn      = aws_iam_role.codepipeline.arn
  pipeline_type = "V2"

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"

    encryption_key {
      id   = aws_kms_key.this.arn
      type = "KMS"
    }
  }

  stage {
    name = "Source"

    action {
      name             = "GitHub"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      namespace        = "SourceVariables"
      output_artifacts = ["SourceArtifact"]

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github.arn
        FullRepositoryId = var.github_repository
        BranchName       = var.github_branch
        DetectChanges    = "true"
        # Clone Git complet : Gitleaks/TruffleHog analysent tout l'historique.
        OutputArtifactFormat = "CODEBUILD_CLONE_REF"
      }
    }
  }

  # Les trois scans tournent en parallèle (même run_order).
  stage {
    name = "Security-Scans"

    dynamic "action" {
      for_each = local.security_scans

      content {
        name            = action.key
        category        = "Test"
        owner           = "AWS"
        provider        = "CodeBuild"
        version         = "1"
        run_order       = 1
        input_artifacts = ["SourceArtifact"]

        configuration = {
          ProjectName          = aws_codebuild_project.this[action.value].name
          EnvironmentVariables = jsonencode(local.pipeline_env)
        }
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Test-Build-Scan-Push"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      namespace        = "BuildVariables"
      input_artifacts  = ["SourceArtifact"]
      output_artifacts = ["BuildEcsArtifact", "BuildEc2Artifact"]

      configuration = {
        ProjectName          = aws_codebuild_project.this["build"].name
        EnvironmentVariables = jsonencode(local.pipeline_env)
      }
    }
  }

  dynamic "stage" {
    for_each = var.require_manual_approval ? [1] : []

    content {
      name = "Approval"

      action {
        name     = "Manual-Approval"
        category = "Approval"
        owner    = "AWS"
        provider = "Manual"
        version  = "1"

        configuration = {
          CustomData = "Image #{BuildVariables.IMAGE_URI} prête : valider le déploiement blue/green."
        }
      }
    }
  }

  stage {
    name = "Deploy-BlueGreen"

    action {
      name            = "ECS-Fargate"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeployToECS"
      version         = "1"
      run_order       = 1
      input_artifacts = ["BuildEcsArtifact"]

      configuration = {
        ApplicationName                = aws_codedeploy_app.ecs.name
        DeploymentGroupName            = aws_codedeploy_deployment_group.ecs.deployment_group_name
        TaskDefinitionTemplateArtifact = "BuildEcsArtifact"
        TaskDefinitionTemplatePath     = "taskdef.json"
        AppSpecTemplateArtifact        = "BuildEcsArtifact"
        AppSpecTemplatePath            = "appspec.yaml"
        Image1ArtifactName             = "BuildEcsArtifact"
        Image1ContainerName            = "IMAGE1_NAME"
      }
    }

    action {
      name            = "EC2-AutoScaling"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeploy"
      version         = "1"
      run_order       = 1
      input_artifacts = ["BuildEc2Artifact"]

      configuration = {
        ApplicationName     = aws_codedeploy_app.ec2.name
        DeploymentGroupName = aws_codedeploy_deployment_group.ec2.deployment_group_name
      }
    }
  }

  stage {
    name = "DAST"

    action {
      name            = "OWASP-ZAP"
      category        = "Test"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceArtifact"]

      configuration = {
        ProjectName = aws_codebuild_project.this["dast"].name
        EnvironmentVariables = jsonencode(concat(local.pipeline_env, [
          { name = "EXPECTED_VERSION", value = "#{BuildVariables.IMAGE_TAG}", type = "PLAINTEXT" },
        ]))
      }
    }
  }
}
