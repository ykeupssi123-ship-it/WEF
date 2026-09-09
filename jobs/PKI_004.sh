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

# CORRIGE LE 2026-09-09 (incident reel sur VM neuve, meme cause que
# PKI_003.sh : factory_ca.crt s'est retrouve VIDE - "openssl req" n'etait
# jamais verifie, et l'ancien test "[ -f factory_ca.crt ]" reconduisait
# le fichier vide indefiniment, meme apres un "repartir a zero" complet
# - le fichier n'est jamais nettoye par MNT_reinstall.sh
# ni par "rm -rf state logs" (PKI_DIR est hors de leur perimetre). La
# consequence reelle etait bien plus grave qu'un simple job en echec :
# PKI_009 copiait ensuite ce certificat vide dans le magasin de confiance
# systeme, cassant la validation TLS sortante (constate en reel : "git
# pull" refusant github.com avec "error setting certificate verify
# locations"). Corrige au meme idiome que PKI_003.sh : le certificat
# n'est valide que s'il EXISTE ET se parse reellement (openssl x509).
if [ "${PKI_MODE:-generate}" = "external" ]; then
  if [ -f "factory_ca.crt" ] && openssl x509 -in factory_ca.crt -noout &>/dev/null; then
    echo "[PKI_004] PKI_MODE=external : factory_ca.crt deja fourni et valide, generation ignoree."
    echo "[PKI_004] OK."
    exit 0
  fi
  if [ -f "factory_ca.crt" ]; then
    echo "[PKI_004] ERREUR : PKI_MODE=external mais ${PKI_DIR}/factory_ca.crt est invalide/corrompu (echec de verification openssl x509)." >&2
    exit 1
  fi
  echo "[PKI_004] ERREUR : PKI_MODE=external mais ${PKI_DIR}/factory_ca.crt est absent."
  echo "[PKI_004] Deposez le certificat de votre CA d'entreprise a cet emplacement puis relancez."
  exit 1
fi

if [ -f "factory_ca.crt" ] && openssl x509 -in factory_ca.crt -noout &>/dev/null; then
  echo "[PKI_004] factory_ca.crt deja present et valide, generation ignoree."
  echo "[PKI_004] OK."
  exit 0
elif [ -f "factory_ca.crt" ]; then
  echo "[PKI_004] AVERTISSEMENT : factory_ca.crt present mais invalide/corrompu (echec de verification openssl x509) - regeneration forcee."
fi

echo "[PKI_004] Generation du certificat CA racine (CN=${PKI_CA_CN})..."
if ! openssl req -new -x509 -sha256 -days "${PKI_DAYS}" \
  -key factory_ca.key -out factory_ca.crt \
  -subj "/CN=${PKI_CA_CN}"; then
  echo "[PKI_004] ERREUR : 'openssl req' a echoue (voir message ci-dessus)." >&2
  exit 1
fi
if ! openssl x509 -in factory_ca.crt -noout &>/dev/null; then
  echo "[PKI_004] ERREUR : factory_ca.crt genere mais invalide a la verification openssl x509 (disque plein ?)." >&2
  exit 1
fi
echo "[PKI_004] OK (certificat verifie valide)."
exit 0
