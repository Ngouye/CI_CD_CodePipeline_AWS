#!/usr/bin/env bash
# Installe les outils de sécurité dans leurs versions épinglées (Linux x86_64).
# Usage : scripts/install-tools.sh gitleaks trufflehog bearer semgrep checkov tfsec trivy dockle
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tool-versions.env
source "$SCRIPT_DIR/tool-versions.env"

BIN_DIR="${BIN_DIR:-/usr/local/bin}"
SUDO=""
if [[ ! -w "$BIN_DIR" ]] && command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# install_release <binaire> <url de l'archive .tar.gz> <sha256 attendu>
install_release() {
  local bin="$1" url="$2" sha="$3" archive="$TMP_DIR/$1.tar.gz"
  curl -sSfL --retry 3 "$url" -o "$archive"
  echo "$sha  $archive" | sha256sum --check --quiet
  tar -xzf "$archive" -C "$TMP_DIR" "$bin"
  $SUDO install -m 0755 "$TMP_DIR/$bin" "$BIN_DIR/$bin"
}

pip_install() {
  python3 -m pip install --quiet --disable-pip-version-check "$@"
}

GH="https://github.com"

for tool in "$@"; do
  echo ">> Installation de $tool"
  case "$tool" in
    gitleaks)
      install_release gitleaks \
        "$GH/gitleaks/gitleaks/releases/download/v$GITLEAKS_VERSION/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" \
        "$GITLEAKS_SHA256" ;;
    trufflehog)
      install_release trufflehog \
        "$GH/trufflesecurity/trufflehog/releases/download/v$TRUFFLEHOG_VERSION/trufflehog_${TRUFFLEHOG_VERSION}_linux_amd64.tar.gz" \
        "$TRUFFLEHOG_SHA256" ;;
    bearer)
      install_release bearer \
        "$GH/Bearer/bearer/releases/download/v$BEARER_VERSION/bearer_${BEARER_VERSION}_linux_amd64.tar.gz" \
        "$BEARER_SHA256" ;;
    tfsec)
      install_release tfsec \
        "$GH/aquasecurity/tfsec/releases/download/v$TFSEC_VERSION/tfsec_${TFSEC_VERSION}_linux_amd64.tar.gz" \
        "$TFSEC_SHA256" ;;
    trivy)
      install_release trivy \
        "$GH/aquasecurity/trivy/releases/download/v$TRIVY_VERSION/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" \
        "$TRIVY_SHA256" ;;
    dockle)
      install_release dockle \
        "$GH/goodwithtech/dockle/releases/download/v$DOCKLE_VERSION/dockle_${DOCKLE_VERSION}_Linux-64bit.tar.gz" \
        "$DOCKLE_SHA256" ;;
    semgrep)
      pip_install "semgrep==$SEMGREP_VERSION" ;;
    checkov)
      pip_install "checkov==$CHECKOV_VERSION" ;;
    *)
      echo "Outil inconnu : $tool" >&2
      exit 1 ;;
  esac
done
