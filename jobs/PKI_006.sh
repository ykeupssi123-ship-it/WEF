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

# CORRIGE LE 2026-09-09 (meme incident/correctif que PKI_003.sh/PKI_004.sh) :
# verification cryptographique reelle au lieu d'une simple presence de
# fichier. factory_server.crt (deja signe) reste un motif de skip a lui
# seul, sans le valider ici - PKI_007 se charge deja de sa propre
# verification (comparaison SAN) et regenere de toute facon si besoin.
if [ -f "factory_server.crt" ]; then
  echo "[PKI_006] Certificat serveur deja signe, CSR non necessaire, ignore."
  echo "[PKI_006] OK."
  exit 0
fi
if [ -f "factory_server.csr" ] && openssl req -in factory_server.csr -noout &>/dev/null; then
  echo "[PKI_006] factory_server.csr deja present et valide, generation ignoree."
  echo "[PKI_006] OK."
  exit 0
elif [ -f "factory_server.csr" ]; then
  echo "[PKI_006] AVERTISSEMENT : factory_server.csr present mais invalide/corrompu - regeneration forcee."
fi

echo "[PKI_006] Generation de la CSR du serveur..."
if ! openssl req -new -key factory_server.key -out factory_server.csr \
  -subj "/CN=factory-server"; then
  echo "[PKI_006] ERREUR : 'openssl req' a echoue (voir message ci-dessus)." >&2
  exit 1
fi
if ! openssl req -in factory_server.csr -noout &>/dev/null; then
  echo "[PKI_006] ERREUR : factory_server.csr genere mais invalide a la verification openssl." >&2
  exit 1
fi
echo "[PKI_006] OK (CSR verifiee valide)."
exit 0
