#!/bin/bash
# rapport_audit.sh - vue d'ensemble de TOUTES les executions de TOUS les
# jobs (pas un job a la fois comme bin/view_history.sh) : qui a marche,
# qui n'a pas marche, combien de fois chacun a tourne. Ajoute le
# 2026-08-12, meme discipline qu'un vrai outil d'ordonnancement
# (Airflow/Control-M/Autosys) : ce n'est pas l'outil qui donne la
# rigueur, c'est la rigueur qui doit tenir meme sans lui.
#
# Usage :
#   ./rapport_audit.sh              -> tableau de tous les jobs ayant un historique
#   ./rapport_audit.sh --echecs     -> uniquement les jobs ayant eu au moins un echec
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LEDGER="$HERE/state/JOBS_HISTORY.csv"
MODE="${1:-}"

if [ ! -f "$LEDGER" ]; then
  echo "Aucun historique pour l'instant (state/JOBS_HISTORY.csv absent)."
  echo "Il se remplit au fur et a mesure des executions de ./orchestrator.sh."
  exit 0
fi

echo "===================================================================="
echo " RAPPORT D'AUDIT - EXECUTIONS DE TOUS LES JOBS"
echo "===================================================================="
TOTAL_RUNS=$(tail -n +2 "$LEDGER" | wc -l)
TOTAL_JOBS=$(tail -n +2 "$LEDGER" | awk -F',' '{print $2}' | sort -u | wc -l)
# FORCE_OK/FORCE_ECHEC (bin/order_job.sh) comptent comme succes/echec dans
# les totaux, mais restent visibles tels quels (colonne DERNIER) -
# jamais confondus avec une execution automatique normale.
TOTAL_OK=$(tail -n +2 "$LEDGER" | awk -F',' '$4=="OK" || $4=="FORCE_OK"' | wc -l)
TOTAL_KO=$(tail -n +2 "$LEDGER" | awk -F',' '$4=="ECHEC" || $4=="FORCE_ECHEC"' | wc -l)
TOTAL_FORCE=$(tail -n +2 "$LEDGER" | awk -F',' '$4=="FORCE_OK" || $4=="FORCE_ECHEC"' | wc -l)
echo "Jobs distincts avec historique : $TOTAL_JOBS"
echo "Executions totales enregistrees : $TOTAL_RUNS (OK: $TOTAL_OK / ECHEC: $TOTAL_KO)"
[ "$TOTAL_FORCE" -gt 0 ] && echo "dont forcees manuellement (./bin/order_job.sh) : $TOTAL_FORCE"
echo ""

printf "%-30s %6s %6s %6s %-8s %s\n" "JOB_ID" "EXECS" "OK" "ECHEC" "DERNIER" "DERNIERE_EXECUTION"
printf "%-30s %6s %6s %6s %-8s %s\n" "------" "-----" "--" "-----" "-------" "-------------------"

tail -n +2 "$LEDGER" | awk -F',' '{print $2}' | sort -u | while IFS= read -r JID; do
  ROWS=$(awk -F',' -v id="$JID" 'NR>1 && $2==id' "$LEDGER")
  NB=$(echo "$ROWS" | wc -l)
  OK=$(echo "$ROWS" | awk -F',' '$4=="OK" || $4=="FORCE_OK"' | wc -l)
  KO=$(echo "$ROWS" | awk -F',' '$4=="ECHEC" || $4=="FORCE_ECHEC"' | wc -l)
  LAST_LINE=$(echo "$ROWS" | tail -1)
  LAST_STATUS=$(echo "$LAST_LINE" | awk -F',' '{print $4}')
  LAST_TS=$(echo "$LAST_LINE" | awk -F',' '{print $1}')
  if [ "$MODE" = "--echecs" ] && [ "$KO" -eq 0 ]; then
    continue
  fi
  printf "%-30s %6s %6s %6s %-8s %s\n" "$JID" "$NB" "$OK" "$KO" "$LAST_STATUS" "$LAST_TS"
done

echo "===================================================================="
echo "Detail d'un job precis : ./bin/view_history.sh <JOB_ID>"
echo "Statistiques/frequence : ./bin/view_history.sh <JOB_ID> stats"
