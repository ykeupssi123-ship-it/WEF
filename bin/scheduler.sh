#!/bin/bash
# bin/scheduler.sh - tick du calendrier natif de l'orchestrateur WEF.
#
# AJOUTE LE 2026-09-18 (demande explicite : "l'orchestrateur doit
# integrer un systeme de calendrier pour savoir quel jour a quelle
# heure quelle minute quelle frequence lancer certains job... ce ne
# sera plus le job qui appelle l'orchestrateur mais c'est l'orchestrateur
# qui sait selon les politiques comment jouer les jobs"). Remplace le
# motif precedent (un job installe SON PROPRE timer systemd independant,
# invisible de l'historique/etat de l'orchestrateur - voir
# jobs/WAZ_053_VT_WATCH_GUARDIAN.sh) par un point de decision central :
# CE script, invoque toutes les 60s par UN SEUL timer systemd
# (setup/wef-scheduler.timer), lit schedules.csv et decide lui-meme quoi
# jouer, quand - exactement comme un vrai crond, jamais un calcul de
# "prochaine echeance" (voir lib/cron_match.sh pour le detail et la
# consequence honnete : un tick manque n'est jamais rattrape).
#
# NE TOUCHE JAMAIS state/*.ok pour decider si un job planifie est "du" -
# ce serait re-utiliser le modele de dependances a mauvais escient (un
# echec planifie supprimerait un marqueur dont d'AUTRES jobs pourraient
# dependre). L'etat du calendrier vit a part, dans state/schedule/.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Meme motif deja etabli pour order.sh/orchestrator.sh (auto-sync AVANT
# de lire vars.conf/jobs_table.csv/schedules.csv) - necessaire ici aussi :
# le coupe-circuit SCHEDULER_ENABLED et schedules.csv doivent toujours
# refleter le dernier `git push`, jamais une copie locale figee.
if [ -d "$HERE/.git" ] && [ -x "$HERE/bin/sync_branch.sh" ]; then
  if ! "$HERE/bin/sync_branch.sh" >/dev/null 2>&1; then
    if git -C "$HERE" status --porcelain 2>/dev/null | grep -q '^UU'; then
      logger -t wef-scheduler "ERREUR : conflit de fusion non resolu (UU) - tick annule, resolvez manuellement."
      exit 1
    fi
    # reseau absent : best-effort, meme tolerance que order.sh/orchestrator.sh
  fi
fi

export VARS_FILE="${VARS_FILE:-$HERE/vars.conf}"
source "$VARS_FILE"
source "$HERE/lib/commun.sh"
source "$HERE/lib/run_job.sh"
source "$HERE/lib/lock.sh"
source "$HERE/lib/cron_match.sh"

# Coupe-circuit, verifie EN PREMIER : un simple changement dans vars.conf
# (deja recupere par le sync ci-dessus) desactive tout, sans jamais
# toucher a systemd sur aucune VM.
if [ "${SCHEDULER_ENABLED:-1}" = "0" ]; then
  exit 0
fi

SCHEDULES_CSV="$HERE/schedules.csv"
[ -f "$SCHEDULES_CSV" ] || exit 0

JOBS_CSV="$HERE/jobs_table.csv"
HISTORY_DIR="$STATE_DIR/history"
HISTORY_LEDGER="$STATE_DIR/JOBS_HISTORY.csv"
RUNNING_DIR="$STATE_DIR/RUNNING"
SCHEDULE_STATE_DIR="$STATE_DIR/schedule"
mkdir -p "$HISTORY_DIR" "$RUNNING_DIR" "$SCHEDULE_STATE_DIR" "$WORK_TMP_DIR"
[ -f "$HISTORY_LEDGER" ] || echo "TIMESTAMP,JOB_ID,JOB_NAME,RESULT,LOG_FILE" > "$HISTORY_LEDGER"

THIS_MINUTE="$(date +%Y%m%d%H%M)"

while IFS=',' read -r S_JOB_ID S_SCHEDULE S_ENABLED; do
  [ "$S_JOB_ID" = "JOB_ID" ] && continue
  [ -z "${S_JOB_ID:-}" ] && continue
  [ "${S_ENABLED:-0}" = "1" ] || continue

  schedule_is_due "$S_SCHEDULE" || continue

  LASTMIN_FILE="$SCHEDULE_STATE_DIR/${S_JOB_ID}.lastmin"
  if [ -f "$LASTMIN_FILE" ] && [ "$(cat "$LASTMIN_FILE" 2>/dev/null)" = "$THIS_MINUTE" ]; then
    continue
  fi

  JOB_ROW="$(grep "^${S_JOB_ID}," "$JOBS_CSV" || true)"
  if [ -z "$JOB_ROW" ]; then
    logger -t wef-scheduler "ERREUR : $S_JOB_ID present dans schedules.csv mais absent de jobs_table.csv - ignore."
    continue
  fi
  IFS=',' read -r C_JOB_ID C_JOB_NAME C_JOB_ROLE C_COMPONENT C_SCRIPT_FILE C_DESC C_IN_COND C_OUT_COND <<< "$JOB_ROW"

  [[ "$C_JOB_ROLE" = "$ROLE" || "$C_JOB_ROLE" = "ALL" ]] || continue
  if [ "$ROLE" = "AGENT_HOST" ]; then
    component_enabled "$C_COMPONENT" || continue
  fi
  if job_held "$S_JOB_ID"; then
    logger -t wef-scheduler "$S_JOB_ID -> GELE (HELD), tick planifie saute."
    continue
  fi
  if job_in_skip_list "$S_JOB_ID"; then
    logger -t wef-scheduler "$S_JOB_ID -> SAUTE_CONFIG (SKIP_JOBS), tick planifie saute."
    continue
  fi

  # Garde-fou (risque identifie en conception, jamais rencontre en
  # pratique) : un job planifie ne devrait jamais alimenter le graphe de
  # dependances - si un autre job consomme son OUT_COND, un echec
  # planifie casserait cette dependance pour tout le monde. "NONE" est
  # explicitement EXCLU : c'est le sentinel projet pour "aucune
  # dependance", jamais une vraie condition - sans cette exclusion,
  # CHAQUE job planifie (qui utilise OUT_COND=NONE par construction)
  # declencherait une fausse alerte contre les dizaines de jobs dont
  # IN_COND=NONE (bug reel trouve par le test fonctionnel de ce script,
  # jamais releve a la simple relecture).
  if [ "$C_OUT_COND" != "NONE" ]; then
    CONSUMERS="$(awk -F',' -v cond="$C_OUT_COND" -v self="$C_JOB_ID" '
      $1 != self && $1 != "JOB_ID" {
        n = split($7, deps, "|")
        for (i=1;i<=n;i++) if (deps[i] == cond) { print $1 }
      }
    ' "$JOBS_CSV")"
    if [ -n "$CONSUMERS" ]; then
      logger -t wef-scheduler "ATTENTION : $S_JOB_ID produit $C_OUT_COND, consomme par [$CONSUMERS] - un job planifie ne devrait jamais alimenter le graphe de dependances. Execute quand meme."
    fi
  fi

  SCRIPT_PATH="$HERE/jobs/$C_SCRIPT_FILE"
  if [ ! -f "$SCRIPT_PATH" ]; then
    logger -t wef-scheduler "ERREUR : script $SCRIPT_PATH introuvable pour $S_JOB_ID."
    continue
  fi

  if ! acquire_run_lock "scheduler.sh:$S_JOB_ID (regle: $S_SCHEDULE)" 0; then
    logger -t wef-scheduler "$S_JOB_ID du a $THIS_MINUTE mais verrou occupe - tente au prochain tick."
    continue
  fi

  check_dev_null

  JOB_TS=$(date +%Y%m%d_%H%M%S_%N)
  mkdir -p "$HISTORY_DIR/$S_JOB_ID"
  JOB_LOG="$HISTORY_DIR/$S_JOB_ID/${JOB_TS}.log"
  {
    echo "=== EXECUTION PLANIFIEE (bin/scheduler.sh) ==="
    echo "Regle schedules.csv : $S_SCHEDULE"
    echo "Date/heure           : $(date -Iseconds)"
    echo "=== Sortie reelle du job ==="
  } > "$JOB_LOG"

  run_job "$S_JOB_ID" "$C_JOB_NAME" "$SCRIPT_PATH" "$JOB_LOG" "$C_OUT_COND" "SCHEDULED_OK" "SCHEDULED_ECHEC"
  JOB_EXIT=$?
  echo "$THIS_MINUTE" > "$LASTMIN_FILE"
  date -Iseconds > "$SCHEDULE_STATE_DIR/${S_JOB_ID}.last"

  if [ $JOB_EXIT -eq 0 ]; then
    logger -t wef-scheduler "$S_JOB_ID -> SCHEDULED_OK. $JOB_LOG"
  else
    logger -t wef-scheduler "$S_JOB_ID -> SCHEDULED_ECHEC. $JOB_LOG"
    if [ -x "$HERE/bin/notify.sh" ]; then
      "$HERE/bin/notify.sh" "$S_JOB_ID" "$C_JOB_NAME (PLANIFIE)" "SCHEDULED_ECHEC" "$JOB_LOG" || true
    fi
  fi

  release_run_lock
done < "$SCHEDULES_CSV"

exit 0
