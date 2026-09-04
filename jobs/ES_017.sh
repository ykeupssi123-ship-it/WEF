#!/bin/bash
# ES_017 - WEF_ES_BLD_BININST - Installation du paquet Elasticsearch
# Version pilotee par ES_PACKAGE_VERSION dans vars.conf (vide = derniere
# version disponible dans le depot ELASTIC_STACK_REPO_MAJOR). Ne desinstalle
# / ne change JAMAIS une version deja en place - le fait uniquement au
# tout premier passage, pour eviter de casser une installation existante.
set -uo pipefail
source "$VARS_FILE"

# CORRIGE LE 2026-08-12 : verifier l'INSTALLATION via le code de retour
# de "rpm -q" (0=installe, 1=absent), pas en supposant que la sortie de
# "--qf" est vide si le paquet est absent - rpm ecrit alors un message
# du style "le paquet X n'est pas installe" SUR STDOUT (texte localise
# selon la langue du systeme), qui se retrouvait capture comme si
# c'etait un vrai numero de version : le paquet n'etait alors JAMAIS
# reinstalle (bug reel observe en deploiement le 2026-08-12, ES_021/
# ES_022/ES_026/ES_027 en cascade sur un paquet elasticsearch absent).
if rpm -q elasticsearch &>/dev/null; then
  INSTALLED_VER=$(rpm -q --qf '%{VERSION}' elasticsearch 2>/dev/null)
  if [ -z "${ES_PACKAGE_VERSION:-}" ] || [ "$INSTALLED_VER" = "${ES_PACKAGE_VERSION}" ]; then
    echo "[ES_017] Paquet elasticsearch deja installe (version ${INSTALLED_VER}), ignore."
  else
    echo "[ES_017] AVERTISSEMENT : version installee (${INSTALLED_VER}) differente de ES_PACKAGE_VERSION (${ES_PACKAGE_VERSION}). Pas de changement automatique (risque de casse) - desinstallez manuellement si vous voulez changer de version."
  fi
  echo "[ES_017] OK."
  exit 0
fi

PKG_SPEC="elasticsearch${ES_PACKAGE_VERSION:+-${ES_PACKAGE_VERSION}}"
echo "[ES_017] Installation du paquet ${PKG_SPEC}..."
dnf install -y "$PKG_SPEC"
echo "[ES_017] OK."
exit 0
