#!/bin/bash
# PKI_009 - WEF_PKI_BLD_SYSTEMTRUST
# Injection de la CA d'usine dans le magasin de confiance de l'OS local,
# pour que curl/dnf valident nativement le TLS interne sans -k.
set -uo pipefail
source "$VARS_FILE"

ANCHOR="/etc/pki/ca-trust/source/anchors/factory_ca.crt"
if [ -f "$ANCHOR" ]; then
  echo "[PKI_009] CA deja injectee dans le magasin de confiance, ignore."
  echo "[PKI_009] OK."
  exit 0
fi

echo "[PKI_009] Injection de la CA d'usine dans le magasin de confiance OS..."
cp "${PKI_DIR}/factory_ca.crt" "$ANCHOR"
update-ca-trust
echo "[PKI_009] OK."
exit 0
