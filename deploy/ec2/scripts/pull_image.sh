#!/bin/bash
# Hook AfterInstall : authentification ECR (rôle d'instance) puis pull de l'image.
set -euo pipefail

# shellcheck source=/dev/null
source /opt/devsecops-app/image.env

REGISTRY="${IMAGE_URI%%/*}"
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"
docker pull "$IMAGE_URI"
