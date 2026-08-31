#!/bin/bash
# PKI_003 - WEF_PKI_BLD_CAKEYGEN
# Generation de la cle privee de la CA racine globale du projet.
#
# Si PKI_MODE=external (PKI d'entreprise deja fournie) : ce job ne
# genere JAMAIS de cle de CA (une PKI externe ne partage pas sa cle
# privee, et on n'en a pas besoin - PKI_004/007 n'en auront pas besoin
# non plus dans ce mode). Il se contente de confirmer et de sortir.
set -uo pipefail
source "$VARS_FILE"
cd "${PKI_DIR}"

if [ "${PKI_MODE:-generate}" = "external" ]; then
  echo "[PKI_003] PKI_MODE=external : aucune cle de CA a generer (fournie par la PKI externe, jamais partagee), ignore."
  echo "[PKI_003] OK."
  exit 0
fi

if [ -f "factory_ca.key" ]; then
  echo "[PKI_003] factory_ca.key deja present, generation ignoree."
  echo "[PKI_003] OK."
  exit 0
fi

echo "[PKI_003] Generation de la cle privee de la CA racine..."
openssl genrsa -out factory_ca.key 2048
echo "[PKI_003] OK."
exit 0
