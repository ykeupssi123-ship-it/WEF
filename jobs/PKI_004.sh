#!/bin/bash
# PKI_004 - WEF_PKI_BLD_CACRTGEN
# Creation du certificat CA racine (FactoryRootCA), x509 auto-signe.
#
# Si PKI_MODE=external : n'invente jamais de CA. Exige que
# factory_ca.crt soit deja depose dans PKI_DIR (copie depuis votre PKI
# d'entreprise) AVANT de lancer l'orchestrateur - erreur claire sinon.
set -uo pipefail
source "$VARS_FILE"
cd "${PKI_DIR}"

if [ "${PKI_MODE:-generate}" = "external" ]; then
  if [ -f "factory_ca.crt" ]; then
    echo "[PKI_004] PKI_MODE=external : factory_ca.crt deja fourni, generation ignoree."
    echo "[PKI_004] OK."
    exit 0
  fi
  echo "[PKI_004] ERREUR : PKI_MODE=external mais ${PKI_DIR}/factory_ca.crt est absent."
  echo "[PKI_004] Deposez le certificat de votre CA d'entreprise a cet emplacement puis relancez."
  exit 1
fi

if [ -f "factory_ca.crt" ]; then
  echo "[PKI_004] factory_ca.crt deja present, generation ignoree."
  echo "[PKI_004] OK."
  exit 0
fi

echo "[PKI_004] Generation du certificat CA racine (CN=${PKI_CA_CN})..."
openssl req -new -x509 -sha256 -days "${PKI_DAYS}" \
  -key factory_ca.key -out factory_ca.crt \
  -subj "/CN=${PKI_CA_CN}"
echo "[PKI_004] OK."
exit 0
