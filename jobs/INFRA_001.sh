#!/bin/bash
# INFRA_001 - WEF_INFRA_BLD_RENAMEELK (VM1)
# Renomme la machine ELK_HOST avec un nom qui parle (ex: wef-elk-core).
# JOB VOLONTAIREMENT ISOLE : aucun autre job ne depend de sa sortie
# (ELK_HOSTNAME_SET n'apparait dans l'IN_CONDITIONS d'aucun autre job).
# Specifique a ce projet/cette machine : supprimable sans casser la
# chaine si ce dossier sert de base a un autre projet.
set -uo pipefail
source "$VARS_FILE"

if [ "${ROLE}" != "ELK_HOST" ]; then
  echo "[INFRA_001] ROLE=${ROLE}, ce job ne concerne que ELK_HOST. Ignore."
  echo "[INFRA_001] OK."
  exit 0
fi

TARGET="${ELK_HOSTNAME:-}"
if [ -z "$TARGET" ]; then
  echo "[INFRA_001] ELK_HOSTNAME est vide dans vars.conf, renommage ignore."
  echo "[INFRA_001] OK."
  exit 0
fi

CURRENT="$(hostname)"
if [ "$CURRENT" = "$TARGET" ]; then
  echo "[INFRA_001] Nom de machine deja '${TARGET}', rien a faire."
  echo "[INFRA_001] OK."
  exit 0
fi

echo "[INFRA_001] Renommage de la machine : ${CURRENT} -> ${TARGET}..."
hostnamectl set-hostname "${TARGET}"
grep -q "127.0.1.1" /etc/hosts && sed -i "s/127.0.1.1.*/127.0.1.1\t${TARGET}/" /etc/hosts || echo -e "127.0.1.1\t${TARGET}" >> /etc/hosts
echo "[INFRA_001] OK."
exit 0
