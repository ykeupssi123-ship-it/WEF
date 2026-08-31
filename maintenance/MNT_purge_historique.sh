#!/bin/bash
# MNT_purge_historique.sh - politique d'expiration de l'historique par
# job (SYSOUT), ajoutee le 2026-08-12. Equivalent fonctionnel de
# l'expiration d'une SYSOUT JCL/mainframe : passe HISTORY_RETENTION_DAYS
# (vars.conf), le job ET son entree de catalogue disparaissent ENSEMBLE
# - jamais un fichier de log orphelin sans ligne de registre, ni une
# ligne de registre qui pointe vers un fichier deja supprime.
#
# Appelee AUTOMATIQUEMENT au demarrage de chaque orchestrator.sh
# (silencieuse, rapide) - reste aussi lancable seule a tout moment :
#   ./maintenance/MNT_purge_historique.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VARS_FILE="${VARS_FILE:-$HERE/vars.conf}"
source "$VARS_FILE"

RETENTION_DAYS="${HISTORY_RETENTION_DAYS:-7}"
LEDGER="${STATE_DIR:-$HERE/state}/JOBS_HISTORY.csv"
HISTORY_DIR="${STATE_DIR:-$HERE/state}/history"

[ -f "$LEDGER" ] || { echo "[MNT_purge_historique] Aucun historique pour l'instant, rien a purger."; exit 0; }

CUTOFF_EPOCH=$(date -d "-${RETENTION_DAYS} days" +%s)
NOW_TAG=$(date -Iseconds)

TMP_LEDGER="${LEDGER}.tmp"
head -1 "$LEDGER" > "$TMP_LEDGER"

KEPT=0
PURGED=0
while IFS=',' read -r TS JOB_ID JOB_NAME RESULT LOGFILE; do
  [ "$TS" = "TIMESTAMP" ] && continue
  [ -z "$TS" ] && continue
  ROW_EPOCH=$(date -d "$TS" +%s 2>/dev/null || echo 0)
  if [ "$ROW_EPOCH" -ge "$CUTOFF_EPOCH" ]; then
    echo "$TS,$JOB_ID,$JOB_NAME,$RESULT,$LOGFILE" >> "$TMP_LEDGER"
    KEPT=$((KEPT+1))
  else
    [ -f "$LOGFILE" ] && rm -f "$LOGFILE"
    PURGED=$((PURGED+1))
  fi
done < "$LEDGER"

mv "$TMP_LEDGER" "$LEDGER"

# Nettoyage des sous-dossiers par job devenus vides (plus aucune
# execution recente pour ce JOB_ID).
if [ -d "$HISTORY_DIR" ]; then
  find "$HISTORY_DIR" -mindepth 1 -maxdepth 1 -type d -empty -delete 2>/dev/null || true
fi

if [ "$PURGED" -gt 0 ]; then
  echo "[MNT_purge_historique] $NOW_TAG : $PURGED execution(s) de plus de ${RETENTION_DAYS} jours purgee(s), $KEPT conservee(s)."
else
  echo "[MNT_purge_historique] Rien a purger (retention ${RETENTION_DAYS} jours, $KEPT execution(s) dans la fenetre)."
fi
