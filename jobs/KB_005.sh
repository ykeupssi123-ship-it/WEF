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
# CORRIGE LE 2026-09-09 (meme incident/correctif que ES_017.sh, meme
# jour : ce job restait, avec ES_017/LS_011, le seul a ne jamais
# verifier "dnf install -y" - meme classe de bug deja corrigee ailleurs
# depuis le 2026-08-19). Corrige selon le meme idiome : code de sortie
# de dnf verifie, retente une fois en forcant l'IPv4, presence reelle
# confirmee par rpm -q apres coup.
if ! dnf install -y "$PKG_SPEC"; then
  echo "[KB_005] AVERTISSEMENT : dnf install a echoue, nouvel essai en forcant l'IPv4 (--setopt=ip_resolve=4, cas connu : IPv6 casse sur certains reseaux/hotspots)..."
  if ! dnf install -y --setopt=ip_resolve=4 "$PKG_SPEC"; then
    echo "[KB_005] ERREUR : dnf install a echoue meme en IPv4 force (voir le message dnf ci-dessus, souvent un depot injoignable/DNS)." >&2
    exit 1
  fi
fi
if ! rpm -q kibana &>/dev/null; then
  echo "[KB_005] ERREUR : dnf s'est termine sans erreur mais kibana n'est toujours pas installe (verification rpm -q)." >&2
  exit 1
fi
echo "[KB_005] OK (confirme installe par rpm -q)."
exit 0
