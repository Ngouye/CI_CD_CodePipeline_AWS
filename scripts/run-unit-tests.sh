#!/usr/bin/env bash
# Tests unitaires + couverture, exécutés dans la même image Node que la production.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

section "Tests unitaires ($NODE_IMAGE)"
docker run --rm \
  -v "$ROOT_DIR/app:/app" \
  -w /app \
  "$NODE_IMAGE" \
  sh -c "npm ci --ignore-scripts --no-audit --no-fund && npm run test:ci"
