#!/bin/bash
# Hook ApplicationStart : lance le conteneur durci (lecture seule, sans capabilities).
set -euo pipefail

# shellcheck source=/dev/null
source /opt/devsecops-app/image.env

CONTAINER_NAME="devsecops-app"

docker run -d \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  --publish 80:8080 \
  --read-only \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --memory 384m \
  --pids-limit 100 \
  --env APP_VERSION="$APP_VERSION" \
  --env DEPLOY_TARGET="Amazon EC2 (Auto Scaling)" \
  "$IMAGE_URI"
