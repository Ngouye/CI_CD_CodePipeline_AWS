#!/usr/bin/env bash
# Scan de l'image Docker AVANT le push : Dockle (bonnes pratiques CIS) + Trivy (CVE).
# Usage : scripts/scan-image.sh <image>
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$ROOT_DIR"

IMAGE="${1:?Usage : scan-image.sh <image>}"

dockle_scan() {
  dockle --format json --output "$REPORTS_DIR/dockle.json" "$IMAGE" || true
  dockle --exit-code 1 --exit-level warn "$IMAGE"
}

trivy_image() {
  local args=(image --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --ignorefile .trivyignore --quiet)
  trivy "${args[@]}" --format sarif --output "$REPORTS_DIR/trivy-image.sarif" "$IMAGE" || return 1
  trivy "${args[@]}" --skip-db-update --exit-code 1 "$IMAGE"
}

run_gate "Dockle" dockle_scan
run_gate "Trivy image" trivy_image
finish
