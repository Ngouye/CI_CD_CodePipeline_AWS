#!/usr/bin/env bash
# Détection de secrets sur tout l'historique Git : Gitleaks + TruffleHog.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$ROOT_DIR"

# Le clone fourni par CodePipeline (CODEBUILD_CLONE_REF) peut être superficiel.
if [[ "$(git rev-parse --is-shallow-repository 2>/dev/null)" == "true" ]]; then
  git fetch --unshallow --quiet || echo "Impossible de récupérer l'historique complet, scan partiel."
fi

gitleaks_scan() {
  gitleaks git . \
    --config .gitleaks.toml \
    --redact \
    --no-banner \
    --verbose \
    --report-format sarif \
    --report-path "$REPORTS_DIR/gitleaks.sarif"
}

# TruffleHog vérifie activement les secrets trouvés (verified) ; les champs
# Raw sont retirés du rapport pour ne jamais recopier un secret en clair.
trufflehog_scan() {
  trufflehog git "file://$ROOT_DIR" \
    --results=verified,unknown \
    --fail \
    --no-update \
    --json \
    | jq -c 'del(.Raw, .RawV2)' \
    | tee "$REPORTS_DIR/trufflehog.json" \
    | jq -r '"\(.DetectorName) — \(.SourceMetadata.Data.Git.file):\(.SourceMetadata.Data.Git.line) (commit \(.SourceMetadata.Data.Git.commit))"'
}

run_gate "Gitleaks" gitleaks_scan
run_gate "TruffleHog" trufflehog_scan
finish
