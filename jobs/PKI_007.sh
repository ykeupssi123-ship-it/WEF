#!/bin/bash
# PKI_007 - WEF_PKI_BLD_SRVCRTSIGN
# Signature du certificat serveur avec SAN multi-hote.
#
# Rejouable sans jamais bloquer un ajout de machine future : au lieu de
# sauter simplement "si le fichier existe", ce job compare le SAN DEJA
# present dans le certificat au SAN ATTENDU (calcule depuis vars.conf).
# S'ils different (ex: vous ajoutez une 3e machine plus tard), le
# certificat est regenere automatiquement. S'ils sont identiques, rien
# n'est refait (idempotent).
#
# FACTORY_HOST_IP peut etre soit une adresse IP, soit un FQDN : ce
# script detecte le format et place la valeur dans le bon type de SAN
# (IP:... ou DNS:...), sinon un FQDN glisse dans "IP:" par erreur et
# openssl le rejette ou le rend invalide.
#
# Si PKI_MODE=external : ne signe/regenere JAMAIS rien (on n'a pas la
# cle privee de la CA d'entreprise, et c'est normal). Exige que
# factory_server.crt soit deja fourni, deja signe par cette CA. Verifie
# juste le SAN et AVERTIT (sans bloquer) s'il ne couvre pas
# FACTORY_HOST_IP - a corriger cote de votre PKI d'entreprise si besoin.
set -uo pipefail
source "$VARS_FILE"
cd "${PKI_DIR}"

is_ip() { [[ "$1" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; }

if [ "${PKI_MODE:-generate}" = "external" ]; then
  if [ ! -f "factory_server.crt" ]; then
    echo "[PKI_007] ERREUR : PKI_MODE=external mais ${PKI_DIR}/factory_server.crt est absent."
    echo "[PKI_007] Deposez le certificat serveur deja signe par votre CA d'entreprise a cet emplacement puis relancez."
    exit 1
  fi
  if [ -n "${FACTORY_HOST_IP:-}" ]; then
    CURRENT_SAN=$(openssl x509 -in factory_server.crt -noout -ext subjectAltName 2>/dev/null | tail -n +2 | xargs)
    if ! echo "$CURRENT_SAN" | grep -q "$FACTORY_HOST_IP"; then
      echo "[PKI_007] AVERTISSEMENT : le SAN du certificat externe (${CURRENT_SAN:-aucun}) ne semble pas couvrir FACTORY_HOST_IP (${FACTORY_HOST_IP}). Les services demarreront quand meme, mais les clients distants risquent de rejeter le certificat - a verifier cote de votre PKI d'entreprise."
    fi
  fi
  echo "[PKI_007] PKI_MODE=external : certificat serveur deja fourni et signe, aucune regeneration."
  echo "[PKI_007] OK."
  exit 0
fi

# Liste des hotes serveur a couvrir : boucle locale + FACTORY_HOST_IP
# (obligatoire) + toute valeur additionnelle dans PKI_EXTRA_SAN_HOSTS
# (variable optionnelle, separee par des virgules, pour couvrir par
# avance une migration ou un renommage sans devoir tout regenerer deux fois).
SAN_ENTRIES=("IP:127.0.0.1" "DNS:localhost")

if [ -n "${FACTORY_HOST_IP:-}" ]; then
  if is_ip "$FACTORY_HOST_IP"; then
    SAN_ENTRIES+=("IP:${FACTORY_HOST_IP}")
  else
    SAN_ENTRIES+=("DNS:${FACTORY_HOST_IP}")
  fi
else
  echo "[PKI_007] ATTENTION : FACTORY_HOST_IP est vide dans vars.conf. Le certificat ne couvrira que 127.0.0.1/localhost."
fi

if [ -n "${PKI_EXTRA_SAN_HOSTS:-}" ]; then
  IFS=',' read -ra EXTRA <<< "${PKI_EXTRA_SAN_HOSTS}"
  for h in "${EXTRA[@]}"; do
    h="$(echo "$h" | xargs)"
    [ -z "$h" ] && continue
    if is_ip "$h"; then SAN_ENTRIES+=("IP:${h}"); else SAN_ENTRIES+=("DNS:${h}"); fi
  done
fi

SAN=$(IFS=,; echo "${SAN_ENTRIES[*]}")

CURRENT_SAN=""
if [ -f "factory_server.crt" ]; then
  CURRENT_SAN=$(openssl x509 -in factory_server.crt -noout -ext subjectAltName 2>/dev/null | tail -n +2 | xargs | sed 's/, /,/g' | sed 's/ Address//g')
fi

if [ -f "factory_server.crt" ] && [ "$CURRENT_SAN" = "$SAN" ]; then
  echo "[PKI_007] Certificat serveur deja a jour (SAN identique : ${SAN}), rien a faire."
  echo "[PKI_007] OK."
  exit 0
fi

if [ -f "factory_server.crt" ]; then
  echo "[PKI_007] SAN change (ancien: ${CURRENT_SAN:-aucun} / nouveau: ${SAN}) -> regeneration du certificat serveur."
else
  echo "[PKI_007] Premiere signature du certificat serveur (SAN=${SAN})."
fi

cat > factory_server-ext.cnf << CNFEOF
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth,clientAuth
subjectAltName=${SAN}
CNFEOF

openssl x509 -req -in factory_server.csr -CA factory_ca.crt -CAkey factory_ca.key \
  -CAcreateserial -out factory_server.crt -days "${PKI_DAYS}" -sha256 \
  -extfile factory_server-ext.cnf

rm -f factory_server-ext.cnf
echo "[PKI_007] OK."
exit 0
