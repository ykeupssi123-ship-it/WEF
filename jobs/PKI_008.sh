#!/bin/bash
# PKI_008 - WEF_PKI_BLD_CHAINGEN
# Construction de la chaine de confiance complete (fullchain).
set -uo pipefail
source "$VARS_FILE"
cd "${PKI_DIR}"

if [ -f "factory_fullchain.pem" ]; then
  echo "[PKI_008] factory_fullchain.pem deja present, generation ignoree."
  echo "[PKI_008] OK."
  exit 0
fi

echo "[PKI_008] Assemblage de la fullchain..."
cat factory_server.crt factory_ca.crt > factory_fullchain.pem
echo "[PKI_008] OK."
exit 0
