#!/usr/bin/env bash
# Archive les rapports de sécurité dans S3 (bucket chiffré KMS du pipeline).
# Usage : scripts/upload-reports.sh <nom-etape>
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

STAGE="${1:?Usage : upload-reports.sh <nom-etape>}"

if [[ -z "${REPORTS_BUCKET:-}" ]]; then
  echo "REPORTS_BUCKET non défini : rapports conservés localement dans $REPORTS_DIR"
  exit 0
fi

DEST="s3://$REPORTS_BUCKET/security-reports/${PIPELINE_EXECUTION_ID:-manual}/$STAGE/"
if aws s3 cp "$REPORTS_DIR" "$DEST" --recursive --only-show-errors; then
  echo "Rapports publiés : $DEST"
else
  echo "AVERTISSEMENT : publication des rapports impossible vers $DEST"
fi
