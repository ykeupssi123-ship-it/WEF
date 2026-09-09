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

# CORRIGE LE 2026-09-09 (incident reel sur VM neuve : factory_ca.crt
# genere par PKI_004 s'est retrouve VIDE (0 octet) car "openssl genrsa"/
# "openssl req" n'etaient jamais verifies ici - meme classe de bug que
# ES_017/KB_005/LS_011 corriges le meme jour, mais avec une consequence
# bien plus grave : une fois le fichier vide present sur disque, l'ancien
# test "[ -f factory_ca.key ]" le considerait "deja present" a chaque
# rejeu (y compris apres un "repartir a zero" complet), reconduisant la
# corruption indefiniment. Corrige : la cle n'est consideree valide que
# si elle EXISTE ET reussit une verification cryptographique reelle
# (openssl rsa -check) - sinon regeneree, meme si le fichier est present.
if [ -f "factory_ca.key" ] && openssl rsa -in factory_ca.key -check -noout &>/dev/null; then
  echo "[PKI_003] factory_ca.key deja present et valide, generation ignoree."
  echo "[PKI_003] OK."
  exit 0
elif [ -f "factory_ca.key" ]; then
  echo "[PKI_003] AVERTISSEMENT : factory_ca.key present mais invalide/corrompu (echec de verification openssl) - regeneration forcee."
fi

echo "[PKI_003] Generation de la cle privee de la CA racine.."
if ! openssl genrsa -out factory_ca.key 2048; then
  echo "[PKI_003] ERREUR : 'openssl genrsa' a echoue (voir message ci-dessus)." >&2
  exit 1
fi
if ! openssl rsa -in factory_ca.key -check -noout &>/dev/null; then
  echo "[PKI_003] ERREUR : factory_ca.key genere mais invalide a la verification openssl (disque plein, entropie insuffisante ?)." >&2
  exit 1
fi
echo "[PKI_003] OK (cle verifiee valide)."
exit 0
