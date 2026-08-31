#!/bin/bash
# ES_045 - WEF_ES_RUN_SSLCONTEST - Rejet des acces reseau non chiffres
set -uo pipefail
source "$VARS_FILE"
echo "[ES_045] Test de poignee de main TLS..."
if echo | openssl s_client -connect 127.0.0.1:${ES_PORT} -CAfile "${PKI_DIR}/factory_ca.crt" 2>&1 | grep -q "Verify return code: 0"; then
  echo "[ES_045] TLS valide et verifie."
  echo "[ES_045] OK."
  exit 0
fi
echo "[ES_045] ERREUR : la poignee de main TLS a echoue ou le certificat n'est pas verifie."
exit 1
