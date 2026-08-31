#!/bin/bash
# WAZ_012 - WEF_WAZ_BLD_DASHINSTLL - Installation du Dashboard natif
# Version pilotee par WAZ_PACKAGE_VERSION (meme variable que WAZ_010/011,
# voir WAZ_010 pour le detail). Ne change jamais une version deja en
# place, seulement au premier passage.
set -uo pipefail
source "$VARS_FILE"

# CORRIGE LE 2026-08-12 (meme bug/correctif que ES_017) : verifier via
# le code de retour de "rpm -q", pas via le contenu de "--qf" qui peut
# porter un message localise "paquet absent" capture comme version.
#
# CORRECTIF 2026-08-19 (meme audit systemique que WAZ_010, wef-elk-core) :
# "dnf install -y" jamais verifie - voir l'en-tete de WAZ_010.sh pour le
# detail complet de l'incident reel (DNS intermittent sur la VM). Meme
# correctif applique ici : code de sortie dnf + presence reelle via
# rpm -q apres coup.
if rpm -q wazuh-dashboard &>/dev/null; then
  INSTALLED_VER=$(rpm -q --qf '%{VERSION}' wazuh-dashboard 2>/dev/null)
  if [ -z "${WAZ_PACKAGE_VERSION:-}" ] || [ "$INSTALLED_VER" = "${WAZ_PACKAGE_VERSION}" ]; then
    echo "[WAZ_012] Deja installe (version ${INSTALLED_VER}), ignore."
  else
    echo "[WAZ_012] AVERTISSEMENT : version installee (${INSTALLED_VER}) differente de WAZ_PACKAGE_VERSION (${WAZ_PACKAGE_VERSION}). Pas de changement automatique - desinstallez manuellement si besoin."
  fi
  echo "[WAZ_012] OK."
  exit 0
fi

PKG_SPEC="wazuh-dashboard${WAZ_PACKAGE_VERSION:+-${WAZ_PACKAGE_VERSION}}"
echo "[WAZ_012] Installation de ${PKG_SPEC}..."
if ! dnf install -y "$PKG_SPEC"; then
  # CORRECTIF 2026-08-19 (meme repli que WAZ_010, voir son en-tete pour le
  # detail complet de l'incident IPv6/hotspot) : reessai automatique en
  # IPv4 force avant d'abandonner.
  echo "[WAZ_012] AVERTISSEMENT : dnf install a echoue, nouvel essai en forcant l'IPv4 (--setopt=ip_resolve=4, cas connu : IPv6 casse sur certains reseaux/hotspots)..."
  if ! dnf install -y --setopt=ip_resolve=4 "$PKG_SPEC"; then
    echo "[WAZ_012] ERREUR : dnf install a echoue meme en IPv4 force (voir le message dnf ci-dessus, souvent un depot injoignable/DNS)." >&2
    exit 1
  fi
fi
if ! rpm -q wazuh-dashboard &>/dev/null; then
  echo "[WAZ_012] ERREUR : dnf s'est termine sans erreur mais wazuh-dashboard n'est toujours pas installe (verification rpm -q)." >&2
  exit 1
fi
echo "[WAZ_012] OK (confirme installe par rpm -q)."
exit 0
