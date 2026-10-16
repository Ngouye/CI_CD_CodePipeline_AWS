#!/usr/bin/env bash
# Fonctions communes aux scripts de scan. À sourcer, pas à exécuter.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORTS_DIR="${REPORTS_DIR:-$ROOT_DIR/reports}"
mkdir -p "$REPORTS_DIR"

# shellcheck source=tool-versions.env
source "$ROOT_DIR/scripts/tool-versions.env"

FAILED_GATES=()

section() {
  printf '\n==================== %s ====================\n' "$*"
}

# run_gate <nom> <commande...>
# Exécute un contrôle bloquant sans interrompre les suivants, pour obtenir
# tous les rapports même si un outil échoue.
run_gate() {
  local name="$1"
  shift
  section "$name"
  if "$@"; then
    echo "[OK] $name"
  else
    echo "[ÉCHEC] $name"
    FAILED_GATES+=("$name")
  fi
}

finish() {
  echo
  if ((${#FAILED_GATES[@]} > 0)); then
    echo "${#FAILED_GATES[@]} contrôle(s) en échec : ${FAILED_GATES[*]}"
    echo "Rapports détaillés : $REPORTS_DIR"
    exit 1
  fi
  echo "Tous les contrôles sont passés. Rapports : $REPORTS_DIR"
}
