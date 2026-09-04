#!/bin/bash
# bin/free_job.sh - Leve le gel manuel (HELD) d'un job, ajoute le
# 2026-08-12. Voir bin/hold_job.sh.
#
# Usage :
#   ./bin/free_job.sh <JOB_ID>
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export VARS_FILE="${VARS_FILE:-$HERE/vars.conf}"
source "$VARS_FILE"
source "$HERE/lib/commun.sh"

JOB_ID="${1:-}"
if [ -z "$JOB_ID" ]; then
  echo "Usage : ./bin/free_job.sh <JOB_ID>"
  exit 1
fi

if ! job_held "$JOB_ID"; then
  echo "$JOB_ID n'est pas gele actuellement. Rien a faire."
  exit 0
fi

echo "Marqueur de gel actuel :"
cat "$STATE_DIR/HELD/${JOB_ID}.held"
rm -f "$STATE_DIR/HELD/${JOB_ID}.held"
echo ""
echo "$JOB_ID LIBERE par $(whoami)@$(hostname 2>/dev/null || echo host-inconnu) le $(date -Iseconds)."
echo "Il repartira normalement au prochain ./orchestrator.sh (si ses dependances sont satisfaites)."
