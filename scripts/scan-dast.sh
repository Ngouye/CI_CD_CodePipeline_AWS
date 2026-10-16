#!/usr/bin/env bash
# Test dynamique (DAST) des environnements déployés avec OWASP ZAP (baseline scan).
# Usage : scripts/scan-dast.sh [url...]   (par défaut : variable TARGET_URLS)
# Si EXPECTED_VERSION est défini, on attend que la cible serve cette version.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$ROOT_DIR"

TARGETS=("$@")
if ((${#TARGETS[@]} == 0)); then
  read -r -a TARGETS <<<"${TARGET_URLS:-}"
fi
if ((${#TARGETS[@]} == 0)); then
  echo "Aucune cible DAST : passer des URLs en argument ou définir TARGET_URLS." >&2
  exit 1
fi

# ZAP tourne sous l'utilisateur "zap" (uid 1000) et écrit dans /zap/wrk.
cp .zap/rules.tsv "$REPORTS_DIR/zap-rules.tsv"
chmod -R a+rwX "$REPORTS_DIR"

wait_for_target() {
  local url="$1" body attempt
  for attempt in $(seq 1 30); do
    if body="$(curl -fsS --max-time 5 "$url/api/info" 2>/dev/null)"; then
      if [[ -z "${EXPECTED_VERSION:-}" ]] || grep -q "\"version\":\"$EXPECTED_VERSION\"" <<<"$body"; then
        echo "Cible prête : $url -> $body"
        return 0
      fi
    fi
    echo "Tentative $attempt/30 : $url pas encore prête..."
    sleep 10
  done
  echo "Cible indisponible ou version inattendue (attendue : ${EXPECTED_VERSION:-n/a})"
  return 1
}

# -I : les WARN ne bloquent pas ; seules les règles passées en FAIL dans .zap/rules.tsv bloquent.
zap_scan() {
  local url="$1" name
  name="$(sed -E 's#^https?://##; s#[^A-Za-z0-9]+#-#g; s#-+$##' <<<"$url")"
  docker run --rm \
    --network "${ZAP_DOCKER_NETWORK:-bridge}" \
    -v "$REPORTS_DIR:/zap/wrk:rw" \
    "$ZAP_IMAGE" \
    zap-baseline.py -t "$url" -c zap-rules.tsv -I -m 2 \
      -r "zap-$name.html" -J "zap-$name.json"
}

for url in "${TARGETS[@]}"; do
  run_gate "Disponibilité $url" wait_for_target "$url"
  run_gate "OWASP ZAP $url" zap_scan "$url"
done
finish
