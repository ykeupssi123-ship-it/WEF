#!/bin/bash
# lib/cron_match.sh - comparateur d'expression cron a 5 champs (minute
# heure jour_mois mois jour_semaine), utilise par bin/scheduler.sh.
#
# AJOUTE LE 2026-09-18 en construisant le systeme de calendrier natif de
# l'orchestrateur (docs/JOURNAL_TECHNIQUE.md). Reproduit le fonctionnement
# reel d'un crond POSIX : a chaque tick, on demande seulement "est-ce que
# MAINTENANT correspond a ce motif ?" - JAMAIS "quelle est la prochaine
# echeance ?". Consequence honnete et voulue : un tick manque (VM eteinte,
# service arrete) est reellement manque, jamais rattrape - exactement le
# comportement d'un vrai cron, pas un raccourci de ce projet.
#
# Support volontairement limite : "*", un entier exact, ou "*/N" (pas de
# listes "1,2,3" ni de plages "1-5") - limite documentee, pas une
# implementation partielle cachee. Restreindre simultanement jour_mois ET
# jour_semaine (tous les deux differents de "*") est refuse : reproduire
# le "OR" reel de cron entre ces deux champs serait une complexite inutile
# pour ce projet.
#
# Aucune dependance a vars.conf/STATE_DIR - fonctions pures, testables en
# isolation (voir le test reel execute avant integration, 2026-09-18).
set -uo pipefail

# cron_field_match <valeur_actuelle> <expression_du_champ> <indexe_a_1:0|1>
# indexe_a_1=1 pour jour_mois/mois (commencent a 1) : "*/N" doit tester
# (valeur-1)%N, jamais valeur%N (correct uniquement pour minute/heure,
# qui commencent a 0).
cron_field_match(){
  local now_raw="$1" expr="$2" one_indexed="${3:-0}"
  local now=$((10#$now_raw))

  [ "$expr" = "*" ] && return 0

  if [[ "$expr" == */* ]]; then
    local step="${expr#*/}"
    [[ "$step" =~ ^[0-9]+$ ]] && [ "$step" -gt 0 ] || return 1
    local base="$now"
    [ "$one_indexed" = "1" ] && base=$((now - 1))
    (( base % step == 0 )) && return 0
    return 1
  fi

  [[ "$expr" =~ ^[0-9]+$ ]] || return 1
  [ "$now" -eq "$((10#$expr))" ] && return 0
  return 1
}

# schedule_matches_time <expr_5_champs> <min> <heure> <jour_mois> <mois> <jour_semaine>
# Fonction pure : les 5 valeurs "actuelles" sont passees en parametres,
# jamais lues depuis `date` ici - c'est ce qui la rend testable avec des
# tuples synthetiques. <jour_semaine> attendu au format `date +%w`
# (0=dimanche..6=samedi).
schedule_matches_time(){
  local expr="$1" now_min="$2" now_hour="$3" now_dom="$4" now_mon="$5" now_dow="$6"
  local f_min f_hour f_dom f_mon f_dow
  read -r f_min f_hour f_dom f_mon f_dow <<< "$expr"
  [ -n "${f_dow:-}" ] || return 1

  if [ "$f_dom" != "*" ] && [ "$f_dow" != "*" ]; then
    echo "[cron_match] ERREUR : expression '$expr' restreint jour_mois ET jour_semaine simultanement - non supporte (limite documentee), traitee comme jamais due." >&2
    return 1
  fi

  [ "$f_dow" = "7" ] && f_dow="0"

  cron_field_match "$now_min" "$f_min" 0 || return 1
  cron_field_match "$now_hour" "$f_hour" 0 || return 1
  cron_field_match "$now_dom" "$f_dom" 1 || return 1
  cron_field_match "$now_mon" "$f_mon" 1 || return 1
  cron_field_match "$now_dow" "$f_dow" 0 || return 1
  return 0
}

# schedule_is_due <expr_5_champs> - lit l'heure REELLE via `date` (usage
# en production, bin/scheduler.sh). schedule_matches_time ci-dessus reste
# la fonction a tester avec des valeurs synthetiques.
schedule_is_due(){
  local expr="$1"
  schedule_matches_time "$expr" "$(date +%M)" "$(date +%H)" "$(date +%d)" "$(date +%m)" "$(date +%w)"
}
