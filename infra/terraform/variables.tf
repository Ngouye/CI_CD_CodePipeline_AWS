variable "aws_region" {
  description = "Région AWS de déploiement."
  type        = string
  default     = "eu-west-3"
}

variable "project_name" {
  description = "Préfixe des ressources (minuscules, chiffres, tirets)."
  type        = string
  default     = "devsecops-cicd"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,15}$", var.project_name))
    error_message = "3 à 16 caractères : minuscules, chiffres et tirets, commençant par une lettre."
  }
}

variable "environment" {
  description = "Nom de l'environnement (demo, staging, prod...)."
  type        = string
  default     = "demo"
}

# --- Source -------------------------------------------------------------------

variable "github_repository" {
  description = "Dépôt GitHub source au format owner/repo."
  type        = string

  validation {
    condition     = can(regex("^[\\w.-]+/[\\w.-]+$", var.github_repository))
    error_message = "Format attendu : owner/repo."
  }
}

variable "github_branch" {
  description = "Branche qui déclenche le pipeline."
  type        = string
  default     = "main"
}

# --- Réseau & calcul ------------------------------------------------------------

variable "vpc_cidr" {
  description = "Plage CIDR du VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "ecs_desired_count" {
  description = "Nombre de tâches Fargate du service ECS."
  type        = number
  default     = 1
}

variable "ec2_instance_type" {
  description = "Type d'instance de la flotte EC2."
  type        = string
  default     = "t3.micro"
}

variable "ec2_desired_capacity" {
  description = "Nombre d'instances EC2 de l'Auto Scaling Group."
  type        = number
  default     = 1
}

variable "bootstrap_image" {
  description = "Image publique servant de placeholder ECS avant le premier passage du pipeline."
  type        = string
  default     = "public.ecr.aws/docker/library/node:22-alpine"
}

variable "test_listener_allowed_cidrs" {
  description = "CIDR autorisés sur le listener de test ECS (8080). Vide = VPC uniquement."
  type        = list(string)
  default     = []
}

# --- Pipeline -------------------------------------------------------------------

variable "codebuild_image" {
  description = "Image d'environnement CodeBuild."
  type        = string
  default     = "aws/codebuild/standard:7.0"
}

variable "require_manual_approval" {
  description = "Ajoute une approbation manuelle entre le build et le déploiement."
  type        = bool
  default     = false
}

variable "ecs_deployment_config" {
  description = "Stratégie de bascule du trafic ECS (AllAtOnce, Canary, Linear)."
  type        = string
  default     = "CodeDeployDefault.ECSAllAtOnce"
}

variable "blue_termination_wait_minutes" {
  description = "Délai avant suppression de l'environnement blue (fenêtre de rollback rapide)."
  type        = number
  default     = 5
}

variable "log_retention_days" {
  description = "Rétention des logs CloudWatch."
  type        = number
  default     = 365
}

# --- SonarQube (optionnel) ----------------------------------------------------------

variable "sonar_host_url" {
  description = "URL SonarQube / SonarCloud (ex. https://sonarcloud.io). Vide = analyse SonarQube désactivée."
  type        = string
  default     = ""
}

variable "sonar_organization" {
  description = "Organisation SonarCloud (inutile pour un SonarQube auto-hébergé)."
  type        = string
  default     = ""
}

variable "sonar_project_key" {
  description = "Clé du projet Sonar (sinon valeur de sonar-project.properties)."
  type        = string
  default     = ""
}

variable "sonar_token_secret_arn" {
  description = "ARN d'un secret Secrets Manager contenant le token Sonar (chaîne brute)."
  type        = string
  default     = ""
}
