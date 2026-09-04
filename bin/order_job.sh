#!/bin/bash
# bin/order_job.sh - Force Start manuel d'un job, ajoute le 2026-08-12.
# Equivalent fonctionnel de l'action "Force" d'un ordonnanceur type
# Control-M/Autosys/JES : demarre un job precis MEME SI ses dependances
# (IN_COND) ne sont pas satisfaites - operation volontairement rare et
# risquee (l'operateur prend la responsabilite que c'est correct de le
# faire malgre tout), jamais silencieuse :
#   - affiche explicitement ce qui manque avant de demander confirmation ;
#   - exige de retaper le JOB_ID exact (pas juste "oui/y") ;
#   - refuse de forcer un job explicitement GELE (HELD) - un gel est une
#     decision d'exploitation deliberee, elle ne doit jamais pouvoir
#     etre court-circuitee par megarde : il faut d'abord bin/free_job.sh ;
#   - exige une RAISON (audit bancaire : aucune derogation manuelle sans
#     justification nominative) - capturee avec l'identite de
#     l'operateur (whoami@hostname) EN TETE du log dedie de cette
#     execution (equivalent SYSOUT), pas dans le registre CSV (qui reste
#     un simple index, jamais un endroit ou stocker du texte libre) ;
#   - passe par EXACTEMENT le meme mecanisme d'historique/marqueur
#     EN_COURS que l'orchestrateur normal (state/history/<JOB_ID>/...,
#     state/RUNNING/<JOB_ID>.running) ;
#   - mais est marque de facon INDELEBILE et DISTINCTE dans le registre
#     (FORCE_OK / FORCE_ECHEC, jamais OK/ECHEC tout court) pour qu'un
#     audit ulterieur sache TOUJOURS qu'un humain a court-circuite le
#     controle de dependances a ce moment precis, meme si le job a
#     reussi.
#
# Usage :
#   ./bin/order_job.sh <JOB_ID> "<raison>"
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export VARS_FILE="${VARS_FILE:-$HERE/vars.conf}"
source "$VARS_FILE"
source "$HERE/lib/commun.sh"

JOB_ID="${1:-}"
RAISON="${2:-}"
if [ -z "$JOB_ID" ] || [ -z "$RAISON" ]; then
  echo "Usage : ./bin/order_job.sh <JOB_ID> \"<raison>\""
  echo "La raison est obligatoire (audit - on ne force jamais un job sans dire pourquoi)."
  echo "Voir ./bin/monitoring.sh pour la liste des jobs EN ATTENTE forcable."
  exit 1
fi
RAISON_SAFE="${RAISON//,/;}"
OPERATEUR="$(whoami)@$(hostname 2>/dev/null || echo host-inconnu)"

JOBS_CSV="$HERE/jobs_table.csv"
HISTORY_DIR="$STATE_DIR/history"
HISTORY_LEDGER="$STATE_DIR/JOBS_HISTORY.csv"
RUNNING_DIR="$STATE_DIR/RUNNING"
mkdir -p "$HISTORY_DIR" "$RUNNING_DIR" "$WORK_TMP_DIR"
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
  echo "etre court-circuitee par un forcage. Liberez-le d'abord si voulu :"
  echo "./bin/free_job.sh $JOB_ID"
  exit 1
fi

if job_done "$C_OUT_COND"; then
  echo "$JOB_ID a deja ete execute avec succes (condition $C_OUT_COND deja remplie)."
  echo "Rien a forcer. Pour le rejouer quand meme, supprimez d'abord state/$C_OUT_COND.ok"
  exit 0
fi

MISSING=""
if [ -n "$C_IN_COND" ] && [ "$C_IN_COND" != "NONE" ]; then
  IFS='|' read -ra deps <<< "$C_IN_COND"
  for d in "${deps[@]}"; do
    job_done "$d" || MISSING="${MISSING}${MISSING:+, }$d"
  done
fi

echo "=================================================="
echo " FORCE START - $JOB_ID ($C_JOB_NAME)"
echo "=================================================="
echo "$C_DESC"
echo ""
echo "Operateur : $OPERATEUR"
echo "Raison    : $RAISON_SAFE"
echo ""
if [ -n "$MISSING" ]; then
  echo "ATTENTION : dependance(s) NON satisfaite(s) : $MISSING"
  echo "Vous vous apprêtez a forcer ce job MALGRE ces conditions manquantes."
  echo "C'est a vous de savoir si c'est correct de le faire (ex: condition"
  echo "remplie manuellement en dehors de l'orchestrateur)."
else
  echo "(Toutes les dependances sont deja satisfaites - ce job aurait de"
  echo "toute facon ete joue au prochain ./orchestrator.sh. Forcage sans risque"
  echo "particulier lie aux dependances.)"
fi
echo ""
read -r -p "Tapez exactement '$JOB_ID' pour confirmer le forcage : " CONFIRM
if [ "$CONFIRM" != "$JOB_ID" ]; then
  echo "Confirmation incorrecte. Forcage annule, rien n'a ete execute."
  exit 1
fi

SCRIPT_PATH="$HERE/jobs/$C_SCRIPT_FILE"
if [ ! -f "$SCRIPT_PATH" ]; then
  echo "ERREUR : script $SCRIPT_PATH introuvable."
  exit 1
fi

JOB_TS=$(date +%Y%m%d_%H%M%S_%N)
mkdir -p "$HISTORY_DIR/$JOB_ID"
JOB_LOG="$HISTORY_DIR/$JOB_ID/${JOB_TS}.log"

# En-tete d'audit AVANT la sortie reelle du job (equivalent SYSOUT) :
# c'est ici, dans le log dedie a CETTE execution, que vivent l'identite
# de l'operateur et la raison - jamais dans le registre CSV.
{
  echo "=== FORCAGE MANUEL (Force Start) ==="
  echo "Operateur   : $OPERATEUR"
  echo "Date/heure  : $(date -Iseconds)"
  echo "Raison      : $RAISON_SAFE"
  echo "Dependance(s) non satisfaite(s) au moment du forcage : ${MISSING:-aucune}"
  echo "=== Sortie reelle du job ==="
} > "$JOB_LOG"

JOB_START_EPOCH=$(date +%s)
# < /dev/null : meme correctif que orchestrator.sh (voir docs/JOURNAL_TECHNIQUE.md, 2026-09-01)
bash "$SCRIPT_PATH" >> "$JOB_LOG" 2>&1 < /dev/null &
JOB_PID=$!
echo "$(date -Iseconds),$JOB_PID,$C_JOB_NAME (FORCE)" > "$RUNNING_DIR/${JOB_ID}.running"
wait "$JOB_PID"
JOB_EXIT=$?
rm -f "$RUNNING_DIR/${JOB_ID}.running"
JOB_DURATION_SEC=$(( $(date +%s) - JOB_START_EPOCH ))

echo "--- Sortie de $JOB_ID ---"
cat "$JOB_LOG"
echo "--- Fin de sortie ---"

if [ $JOB_EXIT -eq 0 ]; then
  mark_done "$C_OUT_COND"
  echo "$(date -Iseconds),$JOB_ID,$C_JOB_NAME,FORCE_OK,$JOB_LOG,$JOB_DURATION_SEC" >> "$HISTORY_LEDGER"
  echo "$JOB_ID -> FORCE_OK ($C_OUT_COND). Marque distinctement dans l'historique"
  echo "(jamais confondu avec une execution normale) : ./bin/view_history.sh $JOB_ID"
  exit 0
else
  echo "$(date -Iseconds),$JOB_ID,$C_JOB_NAME,FORCE_ECHEC,$JOB_LOG,$JOB_DURATION_SEC" >> "$HISTORY_LEDGER"
  echo "$JOB_ID -> FORCE_ECHEC. Voir $JOB_LOG."
  if [ -x "$HERE/notifier.sh" ]; then
    "$HERE/notifier.sh" "$JOB_ID" "$C_JOB_NAME (FORCAGE MANUEL)" "FORCE_ECHEC" "$JOB_LOG" || true
  fi
  exit 1
fi
