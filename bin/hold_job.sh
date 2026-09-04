#!/bin/bash
# bin/hold_job.sh - Gel manuel (HELD) d'un job, ajoute le 2026-08-12.
# Equivalent fonctionnel du statut HELD chez Control-M/Autosys/JES :
# empeche un job de partir MEME SI ses dependances sont satisfaites -
# distinct de EN ATTENTE (qui, lui, se debloque tout seul des que la
# dependance manquante est remplie). Utile pour une fenetre de gel
# deliberee (changement en cours ailleurs, decision d'exploitation).
#
# Usage :
#   ./bin/hold_job.sh <JOB_ID> "<raison>"
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export VARS_FILE="${VARS_FILE:-$HERE/vars.conf}"
source "$VARS_FILE"
source "$HERE/lib/commun.sh"

JOB_ID="${1:-}"
RAISON="${2:-}"
if [ -z "$JOB_ID" ] || [ -z "$RAISON" ]; then
  echo "Usage : ./bin/hold_job.sh <JOB_ID> \"<raison>\""
  echo "La raison est obligatoire (audit - on ne gele jamais un job sans dire pourquoi)."
  exit 1
fi

if ! grep -q "^$JOB_ID," "$HERE/jobs_table.csv"; then
  echo "ERREUR : $JOB_ID introuvable dans jobs_table.csv."
  exit 1
fi

mkdir -p "$STATE_DIR/HELD"
OPERATEUR="$(whoami)@$(hostname 2>/dev/null || echo host-inconnu)"
RAISON_SAFE="${RAISON//,/;}"
{
  echo "TIMESTAMP=$(date -Iseconds)"
  echo "OPERATEUR=$OPERATEUR"
  echo "RAISON=$RAISON_SAFE"
} > "$STATE_DIR/HELD/${JOB_ID}.held"

echo "$JOB_ID GELE (HELD) par $OPERATEUR."
echo "Raison : $RAISON_SAFE"
echo "L'orchestrateur sautera ce job tant qu'il reste gele, meme si ses"
echo "dependances sont satisfaites. Pour le liberer : ./bin/free_job.sh $JOB_ID"
