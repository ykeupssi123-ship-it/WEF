#!/bin/bash
# bin/dossier_check.sh - is the operations workbook still true? Read-only.
#   $APP_BIN/dossier_check.sh            full report
#   $APP_BIN/dossier_check.sh --short    verdict and problems only
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export APP_HOME="${APP_HOME:-$(cd "$HERE/.." && pwd)}"
export STATE_DIR="${STATE_DIR:-$APP_HOME/state}"
exec python3 "$HERE/dossier_check.py" "$@"
