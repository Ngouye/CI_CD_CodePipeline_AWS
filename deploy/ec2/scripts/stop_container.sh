#!/bin/bash
# Hook ApplicationStop : arrête le conteneur de la révision précédente s'il existe.
set -euo pipefail

CONTAINER_NAME="devsecops-app"

if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
  docker rm -f "$CONTAINER_NAME"
fi
