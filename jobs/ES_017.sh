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
# CORRIGE LE 2026-09-09 (incident reel signale par une etudiante en
# deploiement, reproduit a l'identique sur une VM neuve : ce job restait
# le seul, avec KB_005/LS_011, a ne jamais verifier "dnf install -y" -
# meme classe de bug deja corrigee ailleurs le 2026-08-19/08-31 (ES_010,
# FB_004, MB_004, WAG_003, WAZ_010/011/012). Le paquet n'avait pas ete
# reellement installe, mais le job affichait quand meme "[ES_017] OK." -
# la vraie erreur n'apparaissait alors que 4 jobs plus loin, sur ES_021
# ("elasticsearch-keystore : commande introuvable"), sans lien evident
# avec sa cause reelle. Corrige : code de sortie de dnf verifie, retente
# une fois en forcant l'IPv4 (cas connu, voir WAZ_010.sh), et presence
# reelle confirmee par rpm -q apres coup - le job echoue desormais
# bruyamment, tout de suite, avec le vrai message dnf visible dans son
# propre log.
if ! dnf install -y "$PKG_SPEC"; then
  echo "[ES_017] AVERTISSEMENT : dnf install a echoue, nouvel essai en forcant l'IPv4 (--setopt=ip_resolve=4, cas connu : IPv6 casse sur certains reseaux/hotspots)..."
  if ! dnf install -y --setopt=ip_resolve=4 "$PKG_SPEC"; then
    echo "[ES_017] ERREUR : dnf install a echoue meme en IPv4 force (voir le message dnf ci-dessus, souvent un depot injoignable/DNS)." >&2
    exit 1
  fi
fi
if ! rpm -q elasticsearch &>/dev/null; then
  echo "[ES_017] ERREUR : dnf s'est termine sans erreur mais elasticsearch n'est toujours pas installe (verification rpm -q)." >&2
  exit 1
fi
echo "[ES_017] OK (confirme installe par rpm -q)."
exit 0
