#!/bin/bash
# INFRA_002 - WEF_INFRA_BLD_RENAMEBEATS (VM2)
# Renomme la machine BEATS_HOST avec un nom qui parle (ex: wef-beats-sensor).
# JOB VOLONTAIREMENT ISOLE, meme logique que INFRA_001 : supprimable
# sans impact sur les autres jobs pour un autre projet.
set -uo pipefail
source "$VARS_FILE"

if [ "${ROLE}" != "AGENT_HOST" ]; then
  echo "[INFRA_002] ROLE=${ROLE}, ce job ne concerne que AGENT_HOST. Ignore."
  echo "[INFRA_002] OK."
  exit 0
fi

TARGET="${BEATS_HOSTNAME:-}"
if [ -z "$TARGET" ]; then
  echo "[INFRA_002] BEATS_HOSTNAME est vide dans vars.conf, renommage ignore."
  echo "[INFRA_002] OK."
  exit 0
fi

CURRENT="$(hostname)"
if [ "$CURRENT" = "$TARGET" ]; then
  echo "[INFRA_002] Nom de machine deja '${TARGET}', rien a faire."
  echo "[INFRA_002] OK."
  exit 0
fi

echo "[INFRA_002] Renommage de la machine : ${CURRENT} -> ${TARGET}..."
hostnamectl set-hostname "${TARGET}"
grep -q "127.0.1.1" /etc/hosts && sed -i "s/127.0.1.1.*/127.0.1.1\t${TARGET}/" /etc/hosts || echo -e "127.0.1.1\t${TARGET}" >> /etc/hosts
echo "[INFRA_002] OK."
exit 0
