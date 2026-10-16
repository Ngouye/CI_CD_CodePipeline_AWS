#!/usr/bin/env bash
# Scan de l'Infrastructure as Code : Checkov (Terraform, Dockerfile, GitHub Actions) + tfsec.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$ROOT_DIR"

checkov_scan() {
  checkov \
    --directory . \
    --config-file .checkov.yaml \
    --output cli \
    --output sarif \
    --output-file-path "console,$REPORTS_DIR"
}

tfsec_scan() {
  local args=(infra/terraform --minimum-severity HIGH --no-colour)
  tfsec "${args[@]}" --soft-fail --format sarif --out "$REPORTS_DIR/tfsec.sarif" >/dev/null
  tfsec "${args[@]}"
}

run_gate "Checkov" checkov_scan
run_gate "tfsec" tfsec_scan
finish
