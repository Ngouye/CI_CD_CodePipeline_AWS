#!/bin/bash
# Hook ValidateService : l'instance n'entre dans le trafic que si /health répond.
set -euo pipefail

for attempt in $(seq 1 30); do
  if curl -fsS --max-time 3 http://127.0.0.1/health >/dev/null; then
    echo "Service opérationnel (tentative $attempt)"
    exit 0
  fi
  sleep 5
done

echo "Le service ne répond pas sur /health" >&2
docker logs --tail 50 devsecops-app || true
exit 1
