#!/bin/bash
# bin/monitoring.sh - Etat VIVANT de l'orchestrateur, du job en cours (avec
# detection de retard SLA), des jobs EN ATTENTE et des jobs GELES,
# ajoute le 2026-08-12. Equivalent fonctionnel du statut EXECUTING/
# ACTIVE (job en cours), WAITING (bloque sur dependance) et HELD (gele
# manuellement) d'un ordonnanceur type Control-M/Autosys/JES : a
# lancer depuis UN AUTRE terminal pendant qu'./orchestrator.sh tourne
# (ou vient de tourner/s'arreter) sur cette meme machine.
#
# Ne fait JAMAIS confiance a la seule PRESENCE d'un marqueur .running :
# verifie systematiquement que le PID qu'il contient repond encore
# (kill -0). Un marqueur dont le PID ne repond plus = execution
# precedente interrompue brutalement (crash, kill -9, coupure), jamais
# annoncee comme "en cours".
#
# Usage :
#   ./bin/monitoring.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export VARS_FILE="${VARS_FILE:-$HERE/vars.conf}"
source "$VARS_FILE"
source "$HERE/lib/commun.sh"
RUNNING_DIR="${STATE_DIR:-$HERE/state}/RUNNING"
JOBS_CSV="$HERE/jobs_table.csv"
LEDGER="${STATE_DIR:-$HERE/state}/JOBS_HISTORY.csv"

# Duree moyenne historique (colonne 6, DUREE_SEC, ajoutee le
# 2026-08-12) d'un job, calculee sur ses executions passees reussies.
# Vide si moins de 2 echantillons ou colonne absente (executions
# enregistrees avant l'ajout de cette colonne) - jamais invente.
avg_duration(){
  local jid="$1"
  [ -f "$LEDGER" ] || return
  awk -F',' -v id="$jid" '
    NR>1 && $2==id && $4=="OK" && $6 != "" { sum+=$6; n++ }
    END { if (n>=2) printf "%d %d", int(sum/n), n }
  ' "$LEDGER"
}

echo "=================================================="
echo " ETAT VIVANT - $(date '+%Y-%m-%d %H:%M:%S')"
echo "=================================================="

ORCH_MARK="$RUNNING_DIR/_ORCHESTRATEUR.running"
if [ -f "$ORCH_MARK" ]; then
  IFS=',' read -r ORCH_TS ORCH_PID < "$ORCH_MARK"
  if pid_alive "$ORCH_PID"; then
    echo "Orchestrateur : EN COURS (PID $ORCH_PID, demarre le $ORCH_TS)"
  else
    echo "Orchestrateur : MARQUEUR PERIME (PID $ORCH_PID introuvable - execution"
    echo "                interrompue brutalement le $ORCH_TS, sans nettoyage)."
    echo "                Voir state/RAPPORT_EXECUTION.txt pour le dernier etat connu."
  fi
else
  echo "Orchestrateur : ARRETE (aucune execution en cours actuellement)."
fi

echo ""
echo "--- Job(s) EN COURS ---"
FOUND=0
if [ -d "$RUNNING_DIR" ]; then
  for MARK in "$RUNNING_DIR"/*.running; do
    [ -f "$MARK" ] || continue
    BASENAME="$(basename "$MARK" .running)"
    [ "$BASENAME" = "_ORCHESTRATEUR" ] && continue
    FOUND=1
    IFS=',' read -r JTS JPID JNAME < "$MARK"
    if pid_alive "$JPID"; then
      NOW_EPOCH=$(date +%s)
      START_EPOCH=$(date -d "$JTS" +%s 2>/dev/null || echo "$NOW_EPOCH")
      ELAPSED=$((NOW_EPOCH - START_EPOCH))
      ELAPSED_STR="$(printf '%dm%02ds' $((ELAPSED/60)) $((ELAPSED%60)))"
      read -r AVG_SEC AVG_N <<< "$(avg_duration "$BASENAME")"
      if [ -n "${AVG_SEC:-}" ] && [ "$ELAPSED" -gt "$((AVG_SEC * 150 / 100))" ]; then
        AVG_STR="$(printf '%dm%02ds' $((AVG_SEC/60)) $((AVG_SEC%60)))"
        echo "$BASENAME ($JNAME) : EN COURS depuis $ELAPSED_STR (PID $JPID) -- EN RETARD"
        echo "  (moyenne historique sur $AVG_N execution(s) : $AVG_STR - deja plus de 150% de cette moyenne)"
      else
        echo "$BASENAME ($JNAME) : EN COURS depuis $ELAPSED_STR (PID $JPID, demarre le $JTS)"
      fi
    else
      echo "$BASENAME ($JNAME) : MARQUEUR PERIME (PID $JPID introuvable, demarre le $JTS)"
      echo "  -> execution interrompue brutalement. Dernier resultat connu :"
      echo "     ./bin/view_history.sh $BASENAME"
    fi
  done
fi
[ $FOUND -eq 0 ] && echo "(aucun job en cours actuellement)"

echo ""
echo "--- Jobs GELES (HELD - gel manuel operateur, distinct d'une dependance non satisfaite) ---"
HELD_FOUND=0
if [ -d "$STATE_DIR/HELD" ]; then
  for MARK in "$STATE_DIR/HELD"/*.held; do
    [ -f "$MARK" ] || continue
    HELD_FOUND=1
    JID="$(basename "$MARK" .held)"
    OP=$(grep '^OPERATEUR=' "$MARK" | cut -d= -f2-)
    RS=$(grep '^RAISON=' "$MARK" | cut -d= -f2-)
    TS=$(grep '^TIMESTAMP=' "$MARK" | cut -d= -f2-)
    echo "$JID : GELE par $OP le $TS -- $RS"
  done
fi
if [ $HELD_FOUND -eq 0 ]; then
  echo "(aucun job gele actuellement)"
else
  echo ""
  echo "Pour liberer un job gele : ./bin/free_job.sh <JOB_ID>"
fi

echo ""
echo "--- Jobs EN ATTENTE (WAITING - bloques sur une dependance non satisfaite) ---"
WAITING_FOUND=0
if [ -f "$JOBS_CSV" ]; then
  while IFS=',' read -r JOB_ID JOB_NAME JOB_ROLE COMPONENT SCRIPT_FILE DESC IN_COND OUT_COND; do
    [ "$JOB_ID" = "JOB_ID" ] && continue
    [ -z "${JOB_ID:-}" ] && continue
    [[ "$JOB_ROLE" != "${ROLE:-}" && "$JOB_ROLE" != "ALL" ]] && continue
    if [ "${ROLE:-}" = "AGENT_HOST" ]; then
      component_enabled "$COMPONENT" || continue
    fi
    job_done "$OUT_COND" && continue
    # Deja liste sous GELES ci-dessus - pas de double affichage.
    job_held "$JOB_ID" && continue

    MISSING=""
    if [ -n "$IN_COND" ] && [ "$IN_COND" != "NONE" ]; then
      IFS='|' read -ra deps <<< "$IN_COND"
      for d in "${deps[@]}"; do
        job_done "$d" || MISSING="${MISSING}${MISSING:+, }$d"
      done
    fi
    [ -z "$MISSING" ] && continue

    WAITING_FOUND=1
    echo "$JOB_ID ($JOB_NAME) : EN ATTENTE de -> $MISSING"
  done < "$JOBS_CSV"
fi
if [ $WAITING_FOUND -eq 0 ]; then
  echo "(aucun job bloque sur une dependance non satisfaite)"
else
  echo ""
  echo "Pour forcer manuellement un de ces jobs malgre la dependance"
  echo "manquante (equivalent 'Force Start' Control-M) : ./bin/order_job.sh <JOB_ID>"
fi
echo "=================================================="
