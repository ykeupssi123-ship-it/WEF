#!/bin/bash
# bin/set_to_ok.sh - Marque un job comme deja satisfait SANS
# l'executer, ajoute le 2026-08-14 suite a une demande reelle de
# l'operateur (VM1) : bin/hold_job.sh (HELD) bloque tout ce qui depend du
# job gele - inadapte quand le besoin reel est "ce job a deja ete fait
# (ou n'a pas besoin de l'etre), laisse le reste de la chaine continuer
# derriere lui" (ex: sauter ES_001, la mise a jour OS, sans bloquer
# ES_002 et tout ce qui suit).
#
# Distinct des 3 outils existants :
#   - bin/hold_job.sh (HELD)  : "ne joue PAS ce job, meme quand il serait
#                             pret" - bloque tout ce qui en depend.
#   - bin/order_job.sh        : "joue REELLEMENT ce job maintenant, meme
#                             si ses dependances ne sont pas remplies".
#   - bin/set_to_ok.sh : "considere ce job comme deja reussi, SANS
#                             executer son script" - le reste de la
#                             chaine peut continuer.
#
# Meme rigueur d'audit que bin/order_job.sh :
#   - RAISON obligatoire, capturee avec l'identite de l'operateur
#     (whoami@hostname) dans un log dedie a cette "execution" ;
#   - exige de retaper le JOB_ID exact pour confirmer ;
#   - refuse sur un job GELE (HELD) - un gel est une decision distincte,
#     ne doit jamais etre court-circuite silencieusement par un autre
#     outil : liberez-le d'abord si c'est vraiment ce que vous voulez ;
#   - marque de facon INDELEBILE et DISTINCTE dans le registre
#     (MARQUE_FAIT, jamais OK/ECHEC/FORCE_OK) pour qu'un audit ulterieur
#     sache TOUJOURS qu'aucune commande reelle n'a ete executee pour ce
#     job a ce moment precis, meme si tout le reste de la chaine a
#     continue normalement derriere.
#
# Usage :
#   ./bin/set_to_ok.sh <JOB_ID> "<raison>"
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export VARS_FILE="${VARS_FILE:-$HERE/vars.conf}"
source "$VARS_FILE"
source "$HERE/lib/commun.sh"

JOB_ID="${1:-}"
RAISON="${2:-}"
if [ -z "$JOB_ID" ] || [ -z "$RAISON" ]; then
  echo "Usage : ./bin/set_to_ok.sh <JOB_ID> \"<raison>\""
  echo "La raison est obligatoire (audit - on ne marque jamais un job sans dire pourquoi)."
  echo "ATTENTION : ceci ne joue PAS le script du job - ca dit juste a l'orchestrateur"
  echo "de le considerer comme deja reussi. A utiliser seulement si vous savez que la"
  echo "condition qu'il produit (OUT_COND) est deja reellement satisfaite autrement."
  exit 1
fi
RAISON_SAFE="${RAISON//,/;}"
OPERATEUR="$(whoami)@$(hostname 2>/dev/null || echo host-inconnu)"

JOBS_CSV="$HERE/jobs_table.csv"
HISTORY_DIR="$STATE_DIR/history"
HISTORY_LEDGER="$STATE_DIR/JOBS_HISTORY.csv"
mkdir -p "$HISTORY_DIR"
[ -f "$HISTORY_LEDGER" ] || echo "TIMESTAMP,JOB_ID,JOB_NAME,RESULT,LOG_FILE" > "$HISTORY_LEDGER"

LINE=""
while IFS=',' read -r C_JOB_ID C_JOB_NAME C_JOB_ROLE C_COMPONENT C_SCRIPT_FILE C_DESC C_IN_COND C_OUT_COND; do
  [ "$C_JOB_ID" = "$JOB_ID" ] && { LINE=1; break; }
done < "$JOBS_CSV"

if [ -z "$LINE" ]; then
  echo "ERREUR : $JOB_ID introuvable dans jobs_table.csv."
  exit 1
fi

if job_held "$JOB_ID"; then
  echo "ERREUR : $JOB_ID est explicitement GELE (HELD) :"
  cat "$STATE_DIR/HELD/${JOB_ID}.held"
  echo ""
  echo "Un gel est une decision d'exploitation deliberee - elle ne peut pas"
  echo "etre court-circuitee, meme par un marquage manuel. Liberez-le d'abord :"
  echo "./bin/free_job.sh $JOB_ID"
  exit 1
fi

if job_done "$C_OUT_COND"; then
  echo "$JOB_ID est deja marque reussi (condition $C_OUT_COND deja remplie)."
  echo "Rien a faire."
  exit 0
fi

echo "=================================================="
echo " MARQUAGE MANUEL (sans execution) - $JOB_ID ($C_JOB_NAME)"
echo "=================================================="
echo "$C_DESC"
echo ""
echo "Operateur      : $OPERATEUR"
echo "Raison         : $RAISON_SAFE"
echo "Condition posee : $C_OUT_COND"
echo ""
echo "ATTENTION : le script jobs/$C_SCRIPT_FILE ne sera PAS execute."
echo "Vous attestez que la condition ci-dessus est deja reellement"
echo "satisfaite (autrement que par ce job), et que tout ce qui en"
echo "depend peut continuer en toute securite sans que ce script tourne."
echo ""
read -r -p "Tapez exactement '$JOB_ID' pour confirmer le marquage : " CONFIRM
if [ "$CONFIRM" != "$JOB_ID" ]; then
  echo "Confirmation incorrecte. Marquage annule, rien n'a ete modifie."
  exit 1
fi

JOB_TS=$(date +%Y%m%d_%H%M%S_%N)
mkdir -p "$HISTORY_DIR/$JOB_ID"
JOB_LOG="$HISTORY_DIR/$JOB_ID/${JOB_TS}.log"
{
  echo "=== MARQUAGE MANUEL (aucune commande executee) ==="
  echo "Operateur   : $OPERATEUR"
  echo "Date/heure  : $(date -Iseconds)"
  echo "Raison      : $RAISON_SAFE"
  echo "Script jobs/$C_SCRIPT_FILE : NON EXECUTE - ce log ne contient donc pas de"
  echo "sortie de commande, seulement cette attestation d'audit."
} > "$JOB_LOG"

mark_done "$C_OUT_COND"
echo "$(date -Iseconds),$JOB_ID,$C_JOB_NAME,MARQUE_FAIT,$JOB_LOG" >> "$HISTORY_LEDGER"
echo ""
echo "$JOB_ID -> MARQUE_FAIT ($C_OUT_COND). Marque distinctement dans l'historique"
echo "(jamais confondu avec une execution reelle) : ./bin/view_history.sh $JOB_ID"
echo "Relancez ./orchestrator.sh - la chaine continuera derriere ce job."
exit 0
