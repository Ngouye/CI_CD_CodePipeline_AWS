#!/usr/bin/env bash
# Analyse statique du code (SAST) : Semgrep, Bearer et SonarQube (optionnel).
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$ROOT_DIR"

# Semgrep : rapport complet, échec sur les findings ERROR et WARNING (une XSS
# "direct-response-write" est classée WARNING). Les INFO restent informatifs.
semgrep_scan() {
  semgrep scan \
    --config p/default \
    --config p/javascript \
    --config p/expressjs \
    --config p/owasp-top-ten \
    --config p/dockerfile \
    --metrics off \
    --json-output "$REPORTS_DIR/semgrep.json" \
    --sarif-output "$REPORTS_DIR/semgrep.sarif" \
    app/src app/Dockerfile || return 1

  local blocking
  blocking="$(jq '[.results[] | select(.extra.severity == "ERROR" or .extra.severity == "WARNING")] | length' \
    "$REPORTS_DIR/semgrep.json")" || return 1
  echo "Semgrep : $blocking finding(s) bloquant(s) (ERROR / WARNING)"
  [[ "$blocking" -eq 0 ]]
}

# Bearer : sécurité et confidentialité des données, échec sur critical/high.
bearer_scan() {
  local args=(app --skip-path "node_modules,tests,coverage,reports" --severity critical,high --disable-version-check --quiet)
  bearer scan "${args[@]}" --exit-code 0 --format sarif --output "$REPORTS_DIR/bearer.sarif" >/dev/null 2>&1 || true
  bearer scan "${args[@]}"
}

# SonarQube / SonarCloud : qualité + Quality Gate bloquante (couverture incluse).
sonar_scan() {
  (cd app && npm ci --ignore-scripts --no-audit --no-fund && npm run test:ci) || return 1
  local args=(-Dsonar.qualitygate.wait=true -Dsonar.projectVersion="${COMMIT_ID:-local}")
  if [[ -n "${SONAR_PROJECT_KEY:-}" ]]; then args+=(-Dsonar.projectKey="$SONAR_PROJECT_KEY"); fi
  if [[ -n "${SONAR_ORGANIZATION:-}" ]]; then args+=(-Dsonar.organization="$SONAR_ORGANIZATION"); fi
  # SONAR_HOST_URL et SONAR_TOKEN sont lus depuis l'environnement par le scanner.
  npx --yes "@sonar/scan@$SONAR_SCAN_VERSION" "${args[@]}"
}

run_gate "Semgrep" semgrep_scan
run_gate "Bearer" bearer_scan
if [[ -n "${SONAR_HOST_URL:-}" && -n "${SONAR_TOKEN:-}" ]]; then
  run_gate "SonarQube" sonar_scan
else
  section "SonarQube"
  echo "Ignoré : SONAR_HOST_URL / SONAR_TOKEN non définis."
fi
finish
