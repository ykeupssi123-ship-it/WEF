#!/bin/bash
# PKI_006 - WEF_PKI_BLD_SRVCSRGEN
# Generation de la CSR pour le noeud d'ingestion global, sans mot de passe.
#
# Si PKI_MODE=external : aucune CSR a generer (le certificat serveur est
# deja signe par la CA d'entreprise, fourni directement - voir PKI_007).
set -uo pipefail
source "$VARS_FILE"
cd "${PKI_DIR}"

if [ "${PKI_MODE:-generate}" = "external" ]; then
  echo "[PKI_006] PKI_MODE=external : pas de CSR a generer (certificat deja signe fourni), ignore."
  echo "[PKI_006] OK."
  exit 0
fi

if [ -f "factory_server.csr" ] || [ -f "factory_server.crt" ]; then
  echo "[PKI_006] CSR (ou certificat) deja present, generation ignoree."
  echo "[PKI_006] OK."
  exit 0
fi

echo "[PKI_006] Generation de la CSR du serveur..."
openssl req -new -key factory_server.key -out factory_server.csr \
  -subj "/CN=factory-server"
echo "[PKI_006] OK."
exit 0
