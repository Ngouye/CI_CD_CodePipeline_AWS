#!/usr/bin/env bash
# Analyse de composition logicielle (SCA) : vulnérabilités des dépendances npm avec Trivy.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$ROOT_DIR"

trivy_sca() {
  local args=(fs app --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --ignorefile .trivyignore --quiet)
  trivy "${args[@]}" --format sarif --output "$REPORTS_DIR/trivy-sca.sarif" || return 1
  trivy "${args[@]}" --skip-db-update --exit-code 1
}

run_gate "Trivy SCA (dépendances)" trivy_sca
finish
