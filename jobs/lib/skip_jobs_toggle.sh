# skip_jobs_toggle.sh - ajoute/retire des JOB_ID precis de SKIP_JOBS
# (vars.conf) sans jamais toucher aux autres entrees deja presentes
# (ex: SKIP_JOBS="ES_001" de base, jamais notre affaire). Utilise par la
# bascule de mode Kibana<->Wazuh (WAZ_035Ax/WAZ_039Dx) pour mettre en
# pause, le temps de la bascule, les jobs qui presupposent wazuh-indexer
# actif en permanence.
#
# AJOUTE LE 2026-09-03 (refonte demandee par l'utilisateur, voir
# docs/JOURNAL_TECHNIQUE.md). Toujours : sauvegarde avant modification,
# verification apres (meme discipline que chaque edition de fichier de
# configuration critique cette nuit - jamais suppose, toujours confirme
# par grep apres coup).

# add_jobs_to_skip_list "ID1,ID2,ID3" - ajoute ces JOB_ID a SKIP_JOBS
# dans vars.conf (union, jamais de doublon, jamais touche aux entrees
# deja presentes qui ne sont pas dans la liste donnee).
add_jobs_to_skip_list() {
  local ids_to_add="$1"
  local current="${SKIP_JOBS:-}"
  local merged="$current"
  local id
  IFS=',' read -ra NEW_IDS <<< "$ids_to_add"
  for id in "${NEW_IDS[@]}"; do
    [ -z "$id" ] && continue
    if [[ ",${merged}," != *",${id},"* ]]; then
      if [ -z "$merged" ]; then
        merged="$id"
      else
        merged="${merged},${id}"
      fi
    fi
  done
  [ "$merged" = "$current" ] && return 0

  cp -a "$VARS_FILE" "${VARS_FILE}.bak_$(date +%Y%m%d_%H%M%S)"
  if grep -q '^SKIP_JOBS=' "$VARS_FILE"; then
    sed -i "s|^SKIP_JOBS=.*|SKIP_JOBS=\"${merged}\"|" "$VARS_FILE"
  else
    printf '\nSKIP_JOBS="%s"\n' "$merged" >> "$VARS_FILE"
  fi
  if ! grep -q "^SKIP_JOBS=\"${merged}\"\$" "$VARS_FILE"; then
    echo "[skip_jobs_toggle] ERREUR : l'ajout a SKIP_JOBS a echoue (valeur attendue non retrouvee apres ecriture)." >&2
    return 1
  fi
  echo "[skip_jobs_toggle] SKIP_JOBS mis a jour : \"${merged}\""
}

# remove_jobs_from_skip_list "ID1,ID2,ID3" - retire ces JOB_ID precis de
# SKIP_JOBS, laisse toutes les autres entrees intactes.
remove_jobs_from_skip_list() {
  local ids_to_remove="$1"
  local current="${SKIP_JOBS:-}"
  [ -z "$current" ] && return 0
  local remaining=""
  local id kept=0
  IFS=',' read -ra CUR_IDS <<< "$current"
  for id in "${CUR_IDS[@]}"; do
    [ -z "$id" ] && continue
    if [[ ",${ids_to_remove}," == *",${id},"* ]]; then
      continue
    fi
    if [ -z "$remaining" ]; then
      remaining="$id"
    else
      remaining="${remaining},${id}"
    fi
  done
  [ "$remaining" = "$current" ] && return 0

  cp -a "$VARS_FILE" "${VARS_FILE}.bak_$(date +%Y%m%d_%H%M%S)"
  sed -i "s|^SKIP_JOBS=.*|SKIP_JOBS=\"${remaining}\"|" "$VARS_FILE"
  if ! grep -q "^SKIP_JOBS=\"${remaining}\"\$" "$VARS_FILE"; then
    echo "[skip_jobs_toggle] ERREUR : le retrait de SKIP_JOBS a echoue (valeur attendue non retrouvee apres ecriture)." >&2
    return 1
  fi
  echo "[skip_jobs_toggle] SKIP_JOBS mis a jour : \"${remaining}\""
}
