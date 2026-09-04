#!/bin/bash
# ES_018 - WEF_ES_BLD_CRYPCHK - Controle d'acces au coffre PKI neutre
set -uo pipefail
source "$VARS_FILE"
echo "[ES_018] Verification de presence des secrets PKI..."
for f in factory_server.key factory_fullchain.pem; do
  [ -f "${PKI_DIR}/${f}" ] || { echo "[ES_018] ERREUR : ${PKI_DIR}/${f} absent (jobs PKI doivent avoir tourne avant)."; exit 1; }
done
echo "[ES_018] OK."
exit 0
