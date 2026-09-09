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

# CORRIGE LE 2026-09-09 (meme incident/correctif que PKI_003.sh, meme
# jour : verification cryptographique reelle au lieu d'une simple
# presence de fichier, pour ne jamais reconduire une cle corrompue).
if [ "${PKI_MODE:-generate}" = "external" ]; then
  if [ -f "factory_server.key" ] && openssl rsa -in factory_server.key -check -noout &>/dev/null; then
    echo "[PKI_005] PKI_MODE=external : factory_server.key deja fourni et valide, generation ignoree."
    echo "[PKI_005] OK."
    exit 0
  fi
  if [ -f "factory_server.key" ]; then
    echo "[PKI_005] ERREUR : PKI_MODE=external mais ${PKI_DIR}/factory_server.key est invalide/corrompu (echec de verification openssl)." >&2
    exit 1
  fi
  echo "[PKI_005] ERREUR : PKI_MODE=external mais ${PKI_DIR}/factory_server.key est absent."
  echo "[PKI_005] Deposez la cle privee du certificat serveur a cet emplacement puis relancez."
  exit 1
fi

if [ -f "factory_server.key" ] && openssl rsa -in factory_server.key -check -noout &>/dev/null; then
  echo "[PKI_005] factory_server.key deja present et valide, generation ignoree."
  echo "[PKI_005] OK."
  exit 0
elif [ -f "factory_server.key" ]; then
  echo "[PKI_005] AVERTISSEMENT : factory_server.key present mais invalide/corrompu - regeneration forcee."
fi

echo "[PKI_005] Generation de la cle privee du serveur..."
if ! openssl genrsa -out factory_server.key 2048; then
  echo "[PKI_005] ERREUR : 'openssl genrsa' a echoue (voir message ci-dessus)." >&2
  exit 1
fi
if ! openssl rsa -in factory_server.key -check -noout &>/dev/null; then
  echo "[PKI_005] ERREUR : factory_server.key genere mais invalide a la verification openssl." >&2
  exit 1
fi
echo "[PKI_005] OK (cle verifiee valide)."
exit 0
