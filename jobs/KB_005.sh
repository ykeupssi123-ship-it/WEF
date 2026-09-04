#!/bin/bash
# KB_005 - WEF_KB_BLD_BININST - Installation du paquet Kibana
# Version pilotee par KB_PACKAGE_VERSION dans vars.conf (vide = derniere
# version disponible dans le depot ELASTIC_STACK_REPO_MAJOR). Ne change
# jamais une version deja en place, seulement au premier passage.
set -uo pipefail
source "$VARS_FILE"

# CORRIGE LE 2026-08-12 (meme bug/correctif que ES_017) : verifier via
# le code de retour de "rpm -q", pas via le contenu de "--qf" qui peut
# porter un message localise "paquet absent" capture comme version.
if rpm -q kibana &>/dev/null; then
  INSTALLED_VER=$(rpm -q --qf '%{VERSION}' kibana 2>/dev/null)
  if [ -z "${KB_PACKAGE_VERSION:-}" ] || [ "$INSTALLED_VER" = "${KB_PACKAGE_VERSION}" ]; then
    echo "[KB_005] Paquet kibana deja installe (version ${INSTALLED_VER}), ignore."
  else
    echo "[KB_005] AVERTISSEMENT : version installee (${INSTALLED_VER}) differente de KB_PACKAGE_VERSION (${KB_PACKAGE_VERSION}). Pas de changement automatique - desinstallez manuellement si besoin."
  fi
  echo "[KB_005] OK."
  exit 0
fi

PKG_SPEC="kibana${KB_PACKAGE_VERSION:+-${KB_PACKAGE_VERSION}}"
echo "[KB_005] Installation du paquet ${PKG_SPEC}..."
dnf install -y "$PKG_SPEC"
echo "[KB_005] OK."
exit 0
