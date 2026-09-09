# skip_jobs_toggle.sh - ajoute/retire des JOB_ID precis de la liste des
# jobs sautes A L'EXECUTION (pause temporaire), sans jamais toucher au
# SKIP_JOBS de vars.conf (decision humaine, a l'avance, distincte).
# Utilise par la bascule de mode Kibana<->Wazuh (WAZ_035Ax/WAZ_039Dx)
# pour mettre en pause, le temps de la bascule, les jobs qui
# presupposent wazuh-indexer actif en permanence.
#
# AJOUTE LE 2026-09-03 (refonte demandee par l'utilisateur, voir
# docs/JOURNAL_TECHNIQUE.md).
#
# CORRIGE LE 2026-09-09 (incident reel : ce mecanisme ecrivait
# directement dans vars.conf via sed - un fichier VERSIONNE dans Git.
# Chaque bascule Kibana<->Wazuh laissait donc une VRAIE modification
# locale non commitee sur la VM, qui entrait en conflit avec le
# "git pull" du prochain correctif ("Vos modifications locales... seraient
# ecrasees par la fusion") - oblige a un detour git stash/pull/stash pop
# a chaque fois. Cause racine : melange entre configuration D'INTENTION
# (SKIP_JOBS pose par l'operateur dans vars.conf, doit survivre a un git
# pull) et etat D'EXECUTION temporaire (pause du temps d'une bascule,
# ne doit JAMAIS polluer un fichier versionne). Corrige : la pause
# runtime vit desormais dans STATE_DIR/skip_jobs_runtime.conf (deja
# gitignore comme tout STATE_DIR - voir .gitignore) - vars.conf n'est
# plus JAMAIS modifie par un job. job_in_skip_list() (lib/commun.sh)
# consulte desormais les DEUX sources (vars.conf ET ce fichier runtime).
RUNTIME_SKIP_FILE="${STATE_DIR}/skip_jobs_runtime.conf"

_read_runtime_skip() {
  [ -f "$RUNTIME_SKIP_FILE" ] && cat "$RUNTIME_SKIP_FILE" || echo ""
}

# add_jobs_to_skip_list "ID1,ID2,ID3" - ajoute ces JOB_ID a la pause
# runtime (union, jamais de doublon, jamais touche a vars.conf).
add_jobs_to_skip_list() {
  local ids_to_add="$1"
  local current merged id
  current="$(_read_runtime_skip)"
  merged="$current"
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

  echo -n "$merged" > "$RUNTIME_SKIP_FILE"
  if [ "$(cat "$RUNTIME_SKIP_FILE")" != "$merged" ]; then
    echo "[skip_jobs_toggle] ERREUR : l'ajout a la pause runtime a echoue (valeur attendue non retrouvee apres ecriture dans ${RUNTIME_SKIP_FILE})." >&2
    return 1
  fi
  echo "[skip_jobs_toggle] Pause runtime mise a jour (${RUNTIME_SKIP_FILE}) : \"${merged}\""
}

# remove_jobs_from_skip_list "ID1,ID2,ID3" - retire ces JOB_ID precis de
# la pause runtime, laisse les autres entrees runtime intactes (et ne
# touche jamais a SKIP_JOBS dans vars.conf, qui n'est pas de son ressort).
remove_jobs_from_skip_list() {
  local ids_to_remove="$1"
  local current remaining id
  current="$(_read_runtime_skip)"
  [ -z "$current" ] && return 0
  remaining=""
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

  if [ -z "$remaining" ]; then
    rm -f "$RUNTIME_SKIP_FILE"
    echo "[skip_jobs_toggle] Pause runtime videe (${RUNTIME_SKIP_FILE} supprime)."
    return 0
  fi
  echo -n "$remaining" > "$RUNTIME_SKIP_FILE"
  if [ "$(cat "$RUNTIME_SKIP_FILE")" != "$remaining" ]; then
    echo "[skip_jobs_toggle] ERREUR : le retrait de la pause runtime a echoue (valeur attendue non retrouvee apres ecriture dans ${RUNTIME_SKIP_FILE})." >&2
    return 1
  fi
  echo "[skip_jobs_toggle] Pause runtime mise a jour (${RUNTIME_SKIP_FILE}) : \"${remaining}\""
}
