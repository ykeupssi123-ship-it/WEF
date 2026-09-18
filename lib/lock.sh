#!/bin/bash
# lib/lock.sh - verrou d'execution unique, partage par orchestrator.sh,
# bin/order.sh et bin/scheduler.sh.
#
# AJOUTE LE 2026-09-18 en construisant le systeme de calendrier - nouveau
# besoin reel : avant l'ajout de bin/scheduler.sh (declencheur AUTONOME,
# jamais humain), une seule execution pouvait exister a la fois (un
# humain ne lance jamais deux order.sh en meme temps sur la meme
# machine) - aucun verrou n'a donc jamais ete necessaire jusqu'ici
# (confirme avant d'ecrire ce fichier : recherche
# "flock|\.lock|LOCK_FILE|lockfile" dans tout le depot = zero resultat).
# Desormais qu'un timer peut declencher une execution SANS supervision
# humaine, une collision (le scheduler qui demarre pendant qu'un
# operateur est en plein orchestrator.sh, ou pendant un Force-Start)
# devient possible pour la premiere fois - ce fichier ferme ce risque.
#
# A sourcer APRES vars.conf (utilise STATE_DIR).
set -uo pipefail

WEF_RUN_LOCK_FILE="${STATE_DIR}/.wef_run.lock"
WEF_RUN_LOCK_OWNER_FILE="${STATE_DIR}/.wef_run.owner"
WEF_RUN_LOCK_FD=200

# acquire_run_lock <label> [attente_max_secondes=5]
#   <label>              identite lisible (ex: "order.sh:WAG_009 par
#                        root@vm2") - ecrite dans le sidecar .owner, car
#                        flock lui-meme ne porte aucune identite.
#   attente_max_secondes 0 = non bloquant (usage bin/scheduler.sh : un
#                        tick occupe journalise et repart, jamais de
#                        file d'attente de process toutes les 60s).
# Retourne 1 si le verrou n'a pas pu etre pris (jamais d'attente infinie
# meme avec une valeur > 0).
#
# WEF_LOCK_HELD=1 (deja exporte par CE process ou un parent direct) fait
# reussir l'acquisition sans repasser par flock - evite qu'un job qui
# ré-invoquerait order.sh lui-meme se bloque sur son propre verrou.
acquire_run_lock(){
  local label="$1"
  local wait_max="${2:-5}"

  if [ "${WEF_LOCK_HELD:-0}" = "1" ]; then
    return 0
  fi

  eval "exec ${WEF_RUN_LOCK_FD}>>\"\$WEF_RUN_LOCK_FILE\""
  if [ "$wait_max" -eq 0 ]; then
    if ! flock -n "$WEF_RUN_LOCK_FD"; then
      echo "[lock] Verrou d'execution deja detenu - occupe par : $(cat "$WEF_RUN_LOCK_OWNER_FILE" 2>/dev/null || echo inconnu)" >&2
      return 1
    fi
  else
    if ! flock -w "$wait_max" "$WEF_RUN_LOCK_FD"; then
      echo "[lock] Verrou d'execution toujours occupe apres ${wait_max}s - occupe par : $(cat "$WEF_RUN_LOCK_OWNER_FILE" 2>/dev/null || echo inconnu)" >&2
      return 1
    fi
  fi
  echo "$(date -Iseconds),$$,${label}" > "$WEF_RUN_LOCK_OWNER_FILE"
  export WEF_LOCK_HELD=1
  return 0
}

release_run_lock(){
  [ "${WEF_LOCK_HELD:-0}" = "1" ] || return 0
  rm -f "$WEF_RUN_LOCK_OWNER_FILE"
  eval "exec ${WEF_RUN_LOCK_FD}>&-" 2>/dev/null || true
  unset WEF_LOCK_HELD
}
