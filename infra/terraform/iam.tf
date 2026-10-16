# Rôles IAM du pipeline, au plus près du moindre privilège.

locals {
  codedeploy_deployment_config_arn = "arn:aws:codedeploy:${var.aws_region}:${local.account_id}:deploymentconfig:*"
  artifacts_bucket_resources       = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
}

data "aws_iam_policy_document" "assume" {
  for_each = {
    codepipeline = "codepipeline.amazonaws.com"
    codebuild    = "codebuild.amazonaws.com"
    codedeploy   = "codedeploy.amazonaws.com"
    ecs_tasks    = "ecs-tasks.amazonaws.com"
    ec2          = "ec2.amazonaws.com"
  }

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = [each.value]
    }
  }
}

# --- CodePipeline -------------------------------------------------------------------

resource "aws_iam_role" "codepipeline" {
  name               = "${local.name}-codepipeline"
  assume_role_policy = data.aws_iam_policy_document.assume["codepipeline"].json
}

#tfsec:ignore:aws-iam-no-policy-wildcards ecs:RegisterTaskDefinition n'accepte pas de restriction par ressource.
data "aws_iam_policy_document" "codepipeline" {
  statement {
    sid       = "ArtifactStore"
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:GetBucketVersioning", "s3:GetBucketLocation", "s3:PutObject"]
    resources = local.artifacts_bucket_resources
  }

  statement {
    sid       = "Kms"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = [aws_kms_key.this.arn]
  }

  statement {
    sid       = "GitHubConnection"
    actions   = ["codestar-connections:UseConnection", "codeconnections:UseConnection"]
    resources = [aws_codestarconnections_connection.github.arn]
  }

  statement {
    sid       = "CodeBuild"
    actions   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"]
    resources = [for project in aws_codebuild_project.this : project.arn]
  }

  statement {
    sid = "CodeDeploy"
    actions = [
      "codedeploy:CreateDeployment",
      "codedeploy:GetDeployment",
      "codedeploy:GetApplication",
      "codedeploy:GetApplicationRevision",
      "codedeploy:RegisterApplicationRevision",
      "codedeploy:GetDeploymentConfig",
    ]
    resources = [
      aws_codedeploy_app.ecs.arn,
      aws_codedeploy_app.ec2.arn,
      aws_codedeploy_deployment_group.ecs.arn,
      aws_codedeploy_deployment_group.ec2.arn,
      local.codedeploy_deployment_config_arn,
    ]
  }

  statement {
    sid       = "EcsTaskDefinition"
    actions   = ["ecs:RegisterTaskDefinition", "ecs:DescribeTaskDefinition"]
    resources = ["*"]
  }

  statement {
    sid       = "PassEcsTaskRoles"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.ecs_execution.arn, aws_iam_role.ecs_task.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "codepipeline" {
  name   = "codepipeline"
  role   = aws_iam_role.codepipeline.id
  policy = data.aws_iam_policy_document.codepipeline.json
}

# --- CodeBuild ----------------------------------------------------------------------

resource "aws_iam_role" "codebuild" {
  name               = "${local.name}-codebuild"
  assume_role_policy = data.aws_iam_policy_document.assume["codebuild"].json
}

#tfsec:ignore:aws-iam-no-policy-wildcards ecr:GetAuthorizationToken n'accepte que "*" ; les autres "*" sont des suffixes d'ARN.
data "aws_iam_policy_document" "codebuild" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.codebuild.arn}:*"]
  }

  statement {
    sid       = "ArtifactsAndReports"
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:GetBucketAcl", "s3:GetBucketLocation"]
    resources = local.artifacts_bucket_resources
  }

  statement {
    sid       = "Kms"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = [aws_kms_key.this.arn]
  }

  statement {
    sid       = "GitClone"
    actions   = ["codestar-connections:UseConnection", "codeconnections:UseConnection"]
    resources = [aws_codestarconnections_connection.github.arn]
  }

  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [aws_ecr_repository.app.arn]
  }

  statement {
    sid = "TestReports"
    actions = [
      "codebuild:CreateReportGroup",
      "codebuild:CreateReport",
      "codebuild:UpdateReport",
      "codebuild:BatchPutTestCases",
      "codebuild:BatchPutCodeCoverages",
    ]
    resources = ["arn:aws:codebuild:${var.aws_region}:${local.account_id}:report-group/${local.name}-*"]
  }

  dynamic "statement" {
    for_each = var.sonar_token_secret_arn != "" ? [var.sonar_token_secret_arn] : []

    content {
      sid       = "SonarToken"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = [statement.value]
    }
  }
}

resource "aws_iam_role_policy" "codebuild" {
  name   = "codebuild"
  role   = aws_iam_role.codebuild.id
  policy = data.aws_iam_policy_document.codebuild.json
}

# --- CodeDeploy ---------------------------------------------------------------------

resource "aws_iam_role" "codedeploy" {
  name               = "${local.name}-codedeploy"
  assume_role_policy = data.aws_iam_policy_document.assume["codedeploy"].json
}

resource "aws_iam_role_policy_attachment" "codedeploy" {
  for_each = toset([
    "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole",
    "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS",
  ])

  role       = aws_iam_role.codedeploy.name
  policy_arn = each.value
}

# Requis pour copier un ASG basé sur un launch template (blue/green EC2).
#tfsec:ignore:aws-iam-no-policy-wildcards RunInstances porte sur des ressources créées dynamiquement par CodeDeploy.
data "aws_iam_policy_document" "codedeploy_launch_template" {
  statement {
    sid     = "LaunchGreenFleet"
    actions = ["ec2:RunInstances", "ec2:CreateTags"]
    resources = [
      "arn:aws:ec2:${var.aws_region}:${local.account_id}:*",
      "arn:aws:ec2:${var.aws_region}::image/*",
    ]
  }

  statement {
    sid       = "PassInstanceRole"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.ec2.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "codedeploy_launch_template" {
  name   = "launch-template"
  role   = aws_iam_role.codedeploy.id
  policy = data.aws_iam_policy_document.codedeploy_launch_template.json
}

# --- ECS ----------------------------------------------------------------------------

resource "aws_iam_role" "ecs_execution" {
  name               = "${local.name}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.assume["ecs_tasks"].json
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Rôle applicatif volontairement sans permission : l'application n'appelle aucune API AWS.
resource "aws_iam_role" "ecs_task" {
  name               = "${local.name}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.assume["ecs_tasks"].json
}

# --- EC2 ----------------------------------------------------------------------------

resource "aws_iam_role" "ec2" {
  name               = "${local.name}-ec2"
  assume_role_policy = data.aws_iam_policy_document.assume["ec2"].json
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

#tfsec:ignore:aws-iam-no-policy-wildcards ecr:GetAuthorizationToken n'accepte que "*".
data "aws_iam_policy_document" "ec2" {
  statement {
    sid       = "CodeDeployRevisions"
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = ["${aws_s3_bucket.artifacts.arn}/*"]
  }

  statement {
    sid       = "Kms"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = [aws_kms_key.this.arn]
  }

  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid       = "EcrPull"
    actions   = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
    resources = [aws_ecr_repository.app.arn]
  }
}

resource "aws_iam_role_policy" "ec2" {
  name   = "app"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.ec2.json
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${local.name}-ec2"
  role = aws_iam_role.ec2.name
}
