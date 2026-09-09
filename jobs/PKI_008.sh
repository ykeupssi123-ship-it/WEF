#!/bin/bash
# PKI_008 - WEF_PKI_BLD_CHAINGEN
# Construction de la chaine de confiance complete (fullchain).
set -uo pipefail
source "$VARS_FILE"
cd "${PKI_DIR}"

# CORRIGE LE 2026-09-09 (meme incident que PKI_003/004.sh : une source
# vide/corrompue produirait une fullchain vide ou incomplete sans jamais
# etre detectee). "Deja present" ne suffit plus - verifie que le fichier
# contient bien 2 blocs PEM (serveur + CA).
if [ -f "factory_fullchain.pem" ] && [ "$(grep -c 'BEGIN CERTIFICATE' factory_fullchain.pem 2>/dev/null)" = "2" ]; then
  echo "[PKI_008] factory_fullchain.pem deja present et complet, generation ignoree."
  echo "[PKI_008] OK."
  exit 0
elif [ -f "factory_fullchain.pem" ]; then
  echo "[PKI_008] AVERTISSEMENT : factory_fullchain.pem present mais incomplet (pas 2 blocs PEM) - reassemblage force."
fi

if ! openssl x509 -in factory_server.crt -noout &>/dev/null; then
  echo "[PKI_008] ERREUR : factory_server.crt invalide - impossible d'assembler la fullchain." >&2
  exit 1
fi
if ! openssl x509 -in factory_ca.crt -noout &>/dev/null; then
  echo "[PKI_008] ERREUR : factory_ca.crt invalide - impossible d'assembler la fullchain." >&2
  exit 1
fi

echo "[PKI_008] Assemblage de la fullchain..."
cat factory_server.crt factory_ca.crt > factory_fullchain.pem
if [ "$(grep -c 'BEGIN CERTIFICATE' factory_fullchain.pem 2>/dev/null)" != "2" ]; then
  echo "[PKI_008] ERREUR : factory_fullchain.pem genere mais incomplet (pas 2 blocs PEM detectes)." >&2
  exit 1
fi
echo "[PKI_008] OK (fullchain verifiee complete)."
exit 0
