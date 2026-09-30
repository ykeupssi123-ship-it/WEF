#!/bin/bash
# lib/run_job.sh - execution mecanique d'UN job (lancement, attente,
# marqueur .ok, ligne d'historique) - point unique partage par
# orchestrator.sh, bin/order.sh et bin/scheduler.sh.
#
# AJOUTE LE 2026-09-18, en construisant le systeme de calendrier
# (docs/JOURNAL_TECHNIQUE.md). Avant, ce bloc etait duplique a l'identique
# dans orchestrator.sh ET bin/order.sh - un correctif dans l'un (ex: le
# "< /dev/null" du 2026-09-01) exigeait de penser a le refaire dans
# l'autre. En ajoutant bin/scheduler.sh comme TROISIEME appelant, la
# duplication serait devenue triple - extrait ici une fois pour toutes,
# meme motif que lib/commun.sh (voir son en-tete).
#
# A sourcer APRES vars.conf et lib/commun.sh (utilise STATE_DIR indirect
# via mark_done, et $HISTORY_LEDGER/$RUNNING_DIR deja definis par
# l'appelant).
#
# Usage : run_job JOB_ID JOB_NAME SCRIPT_PATH JOB_LOG OUT_COND OK_LABEL FAIL_LABEL
#   - JOB_LOG doit deja exister ET contenir l'en-tete d'audit propre a
#     l'appelant (run normal : rien de special ; Force-Start : identite +
#     raison ; planifie : quelle regle de schedules.csv a declenche) -
#     cette fonction ne fait qu'AJOUTER (>>) la sortie reelle du job,
#     jamais n'ecrase l'en-tete.
#   - OK_LABEL/FAIL_LABEL : le mot exact ecrit dans HISTORY_LEDGER (OK/
#     ECHEC pour un run normal, FORCE_OK/FORCE_ECHEC pour un forcage
#     humain, SCHEDULED_OK/SCHEDULED_ECHEC pour le scheduler) - jamais le
#     meme mot pour deux provenances differentes (principe deja etabli
#     par order.sh avant cette extraction : "jamais confondu avec une
#     execution normale").
#   - Retourne le code de sortie REEL du job. Ne decide JAMAIS d'arreter
#     une chaine, de notifier, ou de continuer - c'est la responsabilite
#     de l'appelant (orchestrator.sh arrete tout au premier echec ;
#     order.sh rend juste compte d'UN job ; scheduler.sh doit continuer
#     vers le prochain job du meme tick meme si celui-ci a echoue).
set -uo pipefail

run_job(){
  local job_id="$1" job_name="$2" script_path="$3" job_log="$4" out_cond="$5" ok_label="$6" fail_label="$7"

  local job_start_epoch job_pid job_exit job_duration_sec running_mark
  job_start_epoch=$(date +%s)

  # REVU LE 2026-09-30 (demande explicite : proteger le contenu des
  # scripts de job contre la simple lecture, sans jamais empecher leur
  # execution). Si jobs.enc/ (setup/encrypt_jobs.sh) existe, tout le
  # dossier jobs/ est dechiffre dans un repertoire prive et EPHEMERE
  # (mktemp -d, 700, detruit juste apres l'execution, succes ou echec) -
  # jamais laisse en clair sur le disque plus longtemps que l'execution
  # elle-meme. Sans jobs.enc/ (projet pas encore chiffre) : comportement
  # EXACTEMENT identique a avant, execution directe depuis jobs/ - voir
  # setup/encrypt_jobs.sh pour ce que cette protection couvre reellement
  # et ce qu'elle ne couvre pas (jamais un DRM, un controle d'acces au
  # code source pour un usage normal).
  local jobs_dir project_root enc_dir script_name enc_script run_path tmp_root=""
  jobs_dir="$(dirname "$script_path")"
  project_root="$(dirname "$jobs_dir")"
  enc_dir="$project_root/jobs.enc"
  script_name="$(basename "$script_path")"
  enc_script="$enc_dir/${script_name}.enc"
  run_path="$script_path"
  local run_vars_file="${VARS_FILE:-}"

  if [ -f "$enc_script" ]; then
    local key_file="${JOBS_ENCRYPTION_KEY_FILE:-$project_root/secrets/jobs_encryption_key.txt}"
    if [ ! -f "$key_file" ]; then
      echo "ERREUR : ${enc_script} existe mais la cle ${key_file} est absente - job REFUSE, jamais execute en clair par contournement." >> "$job_log"
      job_exit=1
      job_duration_sec=$(( $(date +%s) - job_start_epoch ))
      echo "$(date -Iseconds),$job_id,$job_name,$fail_label,$job_log,$job_duration_sec" >> "$HISTORY_LEDGER"
      return 1
    fi
    tmp_root="$(mktemp -d)"
    chmod 700 "$tmp_root"
    local ok=1
    while IFS= read -r -d '' enc_file; do
      local rel="${enc_file#"$enc_dir"/}"
      rel="${rel%.enc}"
      local out_file="$tmp_root/jobs/$rel"
      mkdir -p "$(dirname "$out_file")"
      if ! openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 -salt -pass "file:$key_file" -in "$enc_file" -out "$out_file" 2>>"$job_log"; then
        ok=0
        break
      fi
      chmod 500 "$out_file"
    done < <(find "$enc_dir" -type f -name '*.sh.enc' -print0)
    if [ "$ok" -ne 1 ]; then
      echo "ERREUR : echec du dechiffrement d'un ou plusieurs scripts (cle invalide ?) - job REFUSE." >> "$job_log"
      rm -rf "$tmp_root"
      job_exit=1
      job_duration_sec=$(( $(date +%s) - job_start_epoch ))
      echo "$(date -Iseconds),$job_id,$job_name,$fail_label,$job_log,$job_duration_sec" >> "$HISTORY_LEDGER"
      return 1
    fi
    # Symlink (jamais une copie) : dirname($run_vars_file) doit resoudre
    # a $tmp_root/jobs.. pour que "PROJECT_ROOT=$(dirname $VARS_FILE)"
    # (motif deja utilise par tous les jobs) retrouve les fichiers
    # dechiffres SANS qu'aucun job n'ait besoin d'etre modifie - la
    # cible reelle de vars.conf (secrets compris) reste inchangee.
    ln -s "$run_vars_file" "$tmp_root/vars.conf"
    run_vars_file="$tmp_root/vars.conf"
    run_path="$tmp_root/jobs/$script_name"
  fi

  # < /dev/null : incident reel du 2026-09-01 (voir orchestrator.sh) -
  # sans ca, un job qui lit stdin volerait un octet du flux CSV en cours
  # de lecture par l'appelant (boucle "while read ... < jobs_table.csv").
  VARS_FILE="$run_vars_file" bash "$run_path" >> "$job_log" 2>&1 < /dev/null &
  job_pid=$!
  running_mark="${RUNNING_DIR}/${job_id}.running"
  echo "$(date -Iseconds),$job_pid,$job_name" > "$running_mark"
  wait "$job_pid"
  job_exit=$?
  rm -f "$running_mark"
  [ -n "$tmp_root" ] && rm -rf "$tmp_root"
  job_duration_sec=$(( $(date +%s) - job_start_epoch ))

  if [ "$job_exit" -eq 0 ]; then
    mark_done "$out_cond"
    echo "$(date -Iseconds),$job_id,$job_name,$ok_label,$job_log,$job_duration_sec" >> "$HISTORY_LEDGER"
  else
    echo "$(date -Iseconds),$job_id,$job_name,$fail_label,$job_log,$job_duration_sec" >> "$HISTORY_LEDGER"
  fi
  return "$job_exit"
}
