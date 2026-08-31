#!/bin/bash
# PKI_005 - WEF_PKI_BLD_SRVKEYGEN
# Generation de la cle privee generique pour l'interface reseau (2048 bits).
#
# Si PKI_MODE=external : exige que factory_server.key soit deja depose
# (la cle privee correspondant au certificat serveur deja signe par
# votre CA d'entreprise) - erreur claire sinon, jamais de generation.
set -uo pipefail
source "$VARS_FILE"
cd "${PKI_DIR}"

if [ "${PKI_MODE:-generate}" = "external" ]; then
  if [ -f "factory_server.key" ]; then
    echo "[PKI_005] PKI_MODE=external : factory_server.key deja fourni, generation ignoree."
    echo "[PKI_005] OK."
    exit 0
  fi
  echo "[PKI_005] ERREUR : PKI_MODE=external mais ${PKI_DIR}/factory_server.key est absent."
  echo "[PKI_005] Deposez la cle privee du certificat serveur a cet emplacement puis relancez."
  exit 1
fi

if [ -f "factory_server.key" ]; then
  echo "[PKI_005] factory_server.key deja present, generation ignoree."
  echo "[PKI_005] OK."
  exit 0
fi

echo "[PKI_005] Generation de la cle privee du serveur..."
openssl genrsa -out factory_server.key 2048
echo "[PKI_005] OK."
exit 0
