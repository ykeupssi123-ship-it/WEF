#!/bin/bash
# WAZ_010 - WEF_WAZ_BLD_INDXRINSTLL - Installation de wazuh-indexer
# Version pilotee par WAZ_PACKAGE_VERSION dans vars.conf (vide = derniere
# version disponible dans le depot WAZUH_REPO_MAJOR). Wazuh recommande de
# garder indexer/manager/dashboard sur la MEME version - un seul reglage
# WAZ_PACKAGE_VERSION couvre les 3 (WAZ_010/011/012). Ne change jamais
# une version deja en place, seulement au premier passage.
set -uo pipefail
source "$VARS_FILE"

# CORRIGE LE 2026-08-12 (meme bug/correctif que ES_017) : verifier via
# le code de retour de "rpm -q", pas via le contenu de "--qf" qui peut
# porter un message localise "paquet absent" capture comme version.
#
# CORRECTIF 2026-08-19 (incident reel wef-elk-core) : "dnf install -y"
# n'etait jamais verifie - meme famille d'echec silencieux que les
# incidents 4/107 plus haut. Constate en reel : DNS intermittent sur la
# VM (packages.wazuh.com injoignable par moments, "Could not resolve
# host", confirme aussi par un `ping google.com` qui echouait juste
# apres qu'un `getent hosts` ait reussi - probleme reseau de la machine,
# hors de portee d'un correctif de script) a fait echouer dnf, mais le
# job affichait quand meme "[WAZ_010] OK." - la vraie erreur n'apparaissait
# alors que 4 jobs plus loin, sur WAZ_014 ("Unit wazuh-indexer.service
# not found"), sans lien evident avec sa cause reelle. Corrige : code de
# sortie de dnf verifie ET presence reelle confirmee par rpm -q apres
# coup (double verification, meme idiome que les jobs deja renforces
# ailleurs dans ce projet) - le job echoue desormais bruyamment, tout de
# suite, avec le vrai message dnf visible dans son propre log.
if rpm -q wazuh-indexer &>/dev/null; then
  INSTALLED_VER=$(rpm -q --qf '%{VERSION}' wazuh-indexer 2>/dev/null)
  if [ -z "${WAZ_PACKAGE_VERSION:-}" ] || [ "$INSTALLED_VER" = "${WAZ_PACKAGE_VERSION}" ]; then
    echo "[WAZ_010] Deja installe (version ${INSTALLED_VER}), ignore."
  else
    echo "[WAZ_010] AVERTISSEMENT : version installee (${INSTALLED_VER}) differente de WAZ_PACKAGE_VERSION (${WAZ_PACKAGE_VERSION}). Pas de changement automatique - desinstallez manuellement si besoin."
  fi
  echo "[WAZ_010] OK."
  exit 0
fi

PKG_SPEC="wazuh-indexer${WAZ_PACKAGE_VERSION:+-${WAZ_PACKAGE_VERSION}}"
echo "[WAZ_010] Installation de ${PKG_SPEC}..."
if ! dnf install -y "$PKG_SPEC"; then
  # CORRECTIF 2026-08-19 (2e incident reel le meme jour, wef-elk-core) :
  # le premier echec dnf peut venir d'un IPv6 casse (frequent sur un
  # partage de connexion telephone/hotspot) plutot que d'un vrai probleme
  # DNS - constate en reel : dig/getent resolvaient packages.wazuh.com
  # sans probleme (requetes DNS brutes, jamais IPv6), mais dnf echouait
  # quand meme avec "Could not resolve host name" via libcurl, qui tente
  # une resolution/connexion IPv6 des qu'une adresse IPv6 (meme locale,
  # non fonctionnelle) est presente sur l'interface. --setopt=ip_resolve=4
  # force dnf a ignorer l'IPv6 - a reessayer automatiquement UNE fois
  # avant d'abandonner, jamais impose d'emblee pour ne pas ralentir un
  # reseau IPv6 qui fonctionne correctement ailleurs.
  echo "[WAZ_010] AVERTISSEMENT : dnf install a echoue, nouvel essai en forcant l'IPv4 (--setopt=ip_resolve=4, cas connu : IPv6 casse sur certains reseaux/hotspots)..."
  if ! dnf install -y --setopt=ip_resolve=4 "$PKG_SPEC"; then
    echo "[WAZ_010] ERREUR : dnf install a echoue meme en IPv4 force (voir le message dnf ci-dessus, souvent un depot injoignable/DNS)." >&2
    exit 1
  fi
fi
if ! rpm -q wazuh-indexer &>/dev/null; then
  echo "[WAZ_010] ERREUR : dnf s'est termine sans erreur mais wazuh-indexer n'est toujours pas installe (verification rpm -q)." >&2
  exit 1
fi
echo "[WAZ_010] OK (confirme installe par rpm -q)."
exit 0
