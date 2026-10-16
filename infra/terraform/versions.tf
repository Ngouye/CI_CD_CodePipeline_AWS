terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Pour un usage en équipe, stocker l'état dans S3 (verrouillage natif) :
  # backend "s3" {
  #   bucket       = "mon-bucket-tfstate"
  #   key          = "devsecops-cicd/terraform.tfstate"
  #   region       = "eu-west-3"
  #   encrypt      = true
  #   use_lockfile = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Repository  = var.github_repository
    }
  }
}
