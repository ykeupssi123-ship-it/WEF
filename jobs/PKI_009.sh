#!/bin/bash
# PKI_009 - WEF_PKI_BLD_SYSTEMTRUST
# Injection de la CA d'usine dans le magasin de confiance de l'OS local,
# pour que curl/dnf valident nativement le TLS interne sans -k.
set -uo pipefail
source "$VARS_FILE"

ANCHOR="/etc/pki/ca-trust/source/anchors/factory_ca.crt"

# CORRIGE LE 2026-09-09 (incident reel sur VM neuve) : deux defauts reels
# cumules, trouves en diagnostiquant un "git pull" qui refusait le
# certificat de github.com juste apres un deploiement.
#
# 1) "update-ca-trust" (sans argument) NE regenerait PAS de facon fiable
# /etc/pki/tls/certs/ca-bundle.crt sur cette VM - confirme en reel : le
# fichier restait dans un etat qui faisait echouer toute validation TLS
# sortante (curl/git), jusqu'a ce qu'un "update-ca-trust extract" EXPLICITE
# soit lance a la main, qui a immediatement corrige le probleme. La
# documentation p11-kit distingue bien les sous-commandes (extract/enable/
# disable) - l'appel sans argument n'est pas garanti equivalent selon la
# version. Corrige : "extract" precise explicitement.
#
# 2) L'ancien test "[ -f $ANCHOR ]" ne verifiait que la PRESENCE du
# fichier, jamais son contenu - un factory_ca.crt source deja corrompu
# (voir correctif PKI_004.sh, meme jour) etait copie tel quel dans le
# magasin de confiance systeme, propageant la corruption la ou elle a le
# plus de consequences (TOUT le TLS sortant de la machine). Corrige :
# la source est verifiee AVANT toute copie, et la copie deja en place
# est revalidee elle aussi (jamais reconduite si invalide).
if ! openssl x509 -in "${PKI_DIR}/factory_ca.crt" -noout &>/dev/null; then
  echo "[PKI_009] ERREUR : ${PKI_DIR}/factory_ca.crt est invalide/corrompu - impossible de l'injecter dans le magasin de confiance systeme (voir PKI_004)." >&2
  exit 1
fi

if [ -f "$ANCHOR" ] && openssl x509 -in "$ANCHOR" -noout &>/dev/null; then
  echo "[PKI_009] CA deja injectee et valide dans le magasin de confiance, ignore."
  echo "[PKI_009] OK."
  exit 0
elif [ -f "$ANCHOR" ]; then
  echo "[PKI_009] AVERTISSEMENT : ${ANCHOR} present mais invalide/corrompu - re-injection forcee."
fi

echo "[PKI_009] Injection de la CA d'usine dans le magasin de confiance OS..."
cp "${PKI_DIR}/factory_ca.crt" "$ANCHOR"
if ! update-ca-trust extract; then
  echo "[PKI_009] ERREUR : 'update-ca-trust extract' a echoue (voir message ci-dessus)." >&2
  exit 1
fi
echo "[PKI_009] OK."
exit 0
