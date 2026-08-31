#!/bin/bash
# historique_job.sh - consulte l'historique COMPLET d'un job (toutes ses
# executions, pas seulement la derniere), et le log exact de chacune.
# Ajoute le 2026-08-12 suite a une demande legitime : un .ok ne garde
# que la derniere reussite, ecrase a chaque re-execution - insuffisant
# pour repondre a "ce job a tourne plusieurs fois aujourd'hui, je veux
# voir chacune des sorties".
#
# Usage :
#   ./historique_job.sh                          -> liste les jobs ayant un historique
#   ./historique_job.sh ES_017                    -> liste toutes les executions de ES_017
#   ./historique_job.sh ES_017 3                   -> affiche le log de la 3e execution (ordre chronologique)
#   ./historique_job.sh ES_017 20260812_104500     -> affiche le log dont le timestamp contient ce texte
#   ./historique_job.sh ES_017 stats               -> statistiques (nb executions, taux de reussite,
#                                                       intervalles entre executions - utile pour verifier
#                                                       qu'un job cense tourner regulierement le fait bien)
#   ./historique_job.sh ES_017 stats 300           -> pareil, + signale les intervalles qui s'ecartent de
#                                                       plus de 20% du cycle attendu (300s = toutes les 5 min)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LEDGER="$HERE/state/JOBS_HISTORY.csv"
JOB_ID="${1:-}"

if [ ! -f "$LEDGER" ]; then
  echo "Aucun historique pour l'instant (state/JOBS_HISTORY.csv absent)."
  echo "Il se remplit au fur et a mesure des executions de ./orchestrator.sh."
  exit 0
fi

if [ -z "$JOB_ID" ]; then
  echo "Jobs ayant un historique d'execution :"
  tail -n +2 "$LEDGER" | awk -F',' '{print $2}' | sort -u
  echo ""
  echo "Usage : $0 <JOB_ID> [numero_execution|timestamp]"
  exit 0
fi

MATCHES=$(awk -F',' -v id="$JOB_ID" 'NR>1 && $2==id' "$LEDGER")
if [ -z "$MATCHES" ]; then
  echo "Aucune execution enregistree pour $JOB_ID."
  echo "(Rappel : un job SAUTE car deja marque .ok n'est pas une execution - seuls les jobs qui ont reellement tourne apparaissent ici.)"
  exit 1
fi

SEL="${2:-}"
if [ -z "$SEL" ]; then
  echo "Historique de $JOB_ID (${SEL:+filtre : $SEL}$(echo "$MATCHES" | wc -l) execution(s)) :"
  echo "$MATCHES" | awk -F',' '{printf "  [%d] %s   %-6s   %s\n", NR, $1, $4, $5}'
  echo ""
  echo "Voir le detail d'une execution : $0 $JOB_ID <numero>   ou   $0 $JOB_ID <fragment_timestamp>"
  echo "Voir les statistiques         : $0 $JOB_ID stats"
  exit 0
fi

if [ "$SEL" = "stats" ]; then
  EXPECTED_SEC="${3:-}"
  TOTAL=$(echo "$MATCHES" | wc -l)
  # FORCE_OK/FORCE_ECHEC (forcer_job.sh, ajoute le 2026-08-12) comptent
  # respectivement comme succes/echec pour le taux de reussite - mais
  # restent affiches tels quels (jamais renommes en simple OK/ECHEC)
  # dans le detail liste plus bas, pour qu'un forcage manuel ne soit
  # jamais confondu avec une execution normale de l'orchestrateur.
  OK_COUNT=$(echo "$MATCHES" | awk -F',' '$4=="OK" || $4=="FORCE_OK"' | wc -l)
  KO_COUNT=$(echo "$MATCHES" | awk -F',' '$4=="ECHEC" || $4=="FORCE_ECHEC"' | wc -l)
  FORCE_COUNT=$(echo "$MATCHES" | awk -F',' '$4=="FORCE_OK" || $4=="FORCE_ECHEC"' | wc -l)
  FIRST=$(echo "$MATCHES" | head -1 | awk -F',' '{print $1}')
  LAST=$(echo "$MATCHES" | tail -1 | awk -F',' '{print $1}')
  RATE=$(awk -v o="$OK_COUNT" -v t="$TOTAL" 'BEGIN{printf "%.0f", (o/t)*100}')

  echo "=== Statistiques d'execution : $JOB_ID ==="
  echo "Executions totales : $TOTAL"
  echo "Reussies (OK)       : $OK_COUNT"
  echo "Echouees (ECHEC)    : $KO_COUNT"
  echo "Taux de reussite    : ${RATE}%"
  echo "Premiere execution  : $FIRST"
  echo "Derniere execution  : $LAST"
  [ "$FORCE_COUNT" -gt 0 ] && echo "dont FORCEES manuellement (./forcer_job.sh) : $FORCE_COUNT"

  if [ "$TOTAL" -lt 2 ]; then
    echo ""
    echo "(moins de 2 executions - pas assez de donnees pour calculer un intervalle/une frequence)"
    exit 0
  fi

  echo ""
  echo "--- Intervalles entre executions successives ---"
  echo "$MATCHES" | awk -F',' '{print $1}' | while IFS= read -r ts; do date -d "$ts" +%s; done > /tmp/hj_epochs_$$.txt
  PREV=""
  N=1
  SUM=0
  MIN=""
  MAX=""
  NB_INTERVALS=0
  while IFS= read -r EPOCH; do
    if [ -n "$PREV" ]; then
      DIFF=$((EPOCH - PREV))
      MIN_STR="$(printf '%dm%02ds' $((DIFF/60)) $((DIFF%60)))"
      FLAG=""
      if [ -n "$EXPECTED_SEC" ]; then
        LOW=$((EXPECTED_SEC * 80 / 100))
        HIGH=$((EXPECTED_SEC * 120 / 100))
        if [ "$DIFF" -lt "$LOW" ] || [ "$DIFF" -gt "$HIGH" ]; then
          FLAG="  <-- ECART (attendu ~${EXPECTED_SEC}s, tolerance +/-20%)"
        else
          FLAG="  OK (dans la tolerance du cycle attendu)"
        fi
      fi
      printf "  #%d -> #%d : %s%s\n" "$N" "$((N+1))" "$MIN_STR" "$FLAG"
      SUM=$((SUM + DIFF))
      NB_INTERVALS=$((NB_INTERVALS + 1))
      if [ -z "$MIN" ] || [ "$DIFF" -lt "$MIN" ]; then MIN=$DIFF; fi
      if [ -z "$MAX" ] || [ "$DIFF" -gt "$MAX" ]; then MAX=$DIFF; fi
      N=$((N+1))
    fi
    PREV=$EPOCH
  done < /tmp/hj_epochs_$$.txt
  rm -f /tmp/hj_epochs_$$.txt

  if [ "$NB_INTERVALS" -gt 0 ]; then
    AVG=$((SUM / NB_INTERVALS))
    echo ""
    echo "Intervalle moyen : $(printf '%dm%02ds' $((AVG/60)) $((AVG%60)))"
    echo "Intervalle min   : $(printf '%dm%02ds' $((MIN/60)) $((MIN%60)))"
    echo "Intervalle max   : $(printf '%dm%02ds' $((MAX/60)) $((MAX%60)))"
  fi
  exit 0
fi

if [[ "$SEL" =~ ^[0-9]+$ ]]; then
  LINE=$(echo "$MATCHES" | sed -n "${SEL}p")
else
  LINE=$(echo "$MATCHES" | grep "$SEL" | head -1)
fi

if [ -z "$LINE" ]; then
  echo "Execution introuvable pour la selection '$SEL'."
  echo "Executions disponibles :"
  echo "$MATCHES" | awk -F',' '{printf "  [%d] %s   %-6s\n", NR, $1, $4}'
  exit 1
fi

LOGFILE=$(echo "$LINE" | awk -F',' '{print $5}')
echo "=== $JOB_ID - $(echo "$LINE" | awk -F',' '{print $1}') -> $(echo "$LINE" | awk -F',' '{print $4}') ==="
echo "--- log complet de cette execution ---"
if [ -f "$LOGFILE" ]; then
  cat "$LOGFILE"
else
  echo "(fichier de log introuvable : $LOGFILE)"
fi
