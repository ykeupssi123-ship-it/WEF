#!/bin/bash
# LS_011 - WEF_LS_BLD_BININST - Installation du paquet Logstash
# Version pilotee par LS_PACKAGE_VERSION dans vars.conf (vide = derniere
# version disponible dans le depot ELASTIC_STACK_REPO_MAJOR). Ne change
# jamais une version deja en place, seulement au premier passage.
set -uo pipefail
source "$VARS_FILE"

# CORRIGE LE 2026-08-12 (meme bug/correctif que ES_017) : verifier via
# le code de retour de "rpm -q", pas via le contenu de "--qf" qui peut
# porter un message localise "paquet absent" capture comme version.
if rpm -q logstash &>/dev/null; then
  INSTALLED_VER=$(rpm -q --qf '%{VERSION}' logstash 2>/dev/null)
  if [ -z "${LS_PACKAGE_VERSION:-}" ] || [ "$INSTALLED_VER" = "${LS_PACKAGE_VERSION}" ]; then
    echo "[LS_011] Paquet logstash deja installe (version ${INSTALLED_VER}), ignore."
  else
    echo "[LS_011] AVERTISSEMENT : version installee (${INSTALLED_VER}) differente de LS_PACKAGE_VERSION (${LS_PACKAGE_VERSION}). Pas de changement automatique - desinstallez manuellement si besoin."
  fi
  echo "[LS_011] OK."
  exit 0
fi

PKG_SPEC="logstash${LS_PACKAGE_VERSION:+-${LS_PACKAGE_VERSION}}"
echo "[LS_011] Installation du paquet ${PKG_SPEC}..."
dnf install -y "$PKG_SPEC"
echo "[LS_011] OK."
exit 0
