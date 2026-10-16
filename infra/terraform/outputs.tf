output "ecs_app_url" {
  description = "URL de l'application déployée sur ECS Fargate."
  value       = "http://${aws_lb.ecs.dns_name}"
}

output "ec2_app_url" {
  description = "URL de l'application déployée sur EC2."
  value       = "http://${aws_lb.ec2.dns_name}"
}

output "ecr_repository_url" {
  description = "Dépôt ECR des images applicatives."
  value       = aws_ecr_repository.app.repository_url
}

output "pipeline_url" {
  description = "Console AWS du pipeline."
  value       = "https://${var.aws_region}.console.aws.amazon.com/codesuite/codepipeline/pipelines/${aws_codepipeline.this.name}/view?region=${var.aws_region}"
}

output "github_connection_url" {
  description = "Connexion GitHub à activer une fois (statut PENDING après création)."
  value       = "https://${var.aws_region}.console.aws.amazon.com/codesuite/settings/connections?region=${var.aws_region}"
}

output "security_reports_location" {
  description = "Emplacement des rapports de sécurité de chaque exécution."
  value       = "s3://${aws_s3_bucket.artifacts.bucket}/security-reports/"
}
