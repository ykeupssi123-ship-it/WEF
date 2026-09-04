#!/bin/bash
# FB_004 - WEF_FB_BLD_BININST - Installation du paquet Filebeat
# Version pilotee par FB_PACKAGE_VERSION dans vars.conf (vide = derniere
# version disponible dans le depot ELASTIC_STACK_REPO_MAJOR). Ne change
# jamais une version deja en place, seulement au premier passage.
#
# CORRIGE LE 2026-08-31 (incident reel, premier deploiement d'agent sur
# 192.168.50.130) : "dnf install -y" n'etait jamais verifie - ce job a
# affiche "OK" alors que filebeat n'a jamais ete installe (confirme en
# reel : rpm -q filebeat -> absent, juste apres ce job). Cause reelle :
# echec de resolution DNS du depot "filebeat" lui-meme pendant le
# rafraichissement des metadonnees dnf (incident IPv6/DNS deja documente
# dans WAZ_010.sh), jamais detecte faute de verification apres coup.
# Meme correctif que WAG_003.sh/WAZ_010.sh/WAZ_012.sh/DNS_001.sh : code
# de sortie dnf verifie, repli IPv4, presence reelle confirmee via
# rpm -q.
#
# CORRIGE LE 2026-08-31 (meme jour, incident reel : ce meme "dnf install"
# a pris plus de 20 MINUTES pour un seul paquet, sans etre bloque -
# confirme en reel via /proc/<pid>/io : debit reseau/disque authentique,
# solveur de dependances libsolv genuinement actif, pas un blocage).
# Cause reelle : le depot combine officiel Elastic
# (artifacts.elastic.co/packages/8.x/yum, ecrit par FB_003.sh) regroupe
# TOUS les produits Elastic (Elasticsearch/Kibana/Logstash/Filebeat/
# Metricbeat/APM...) sur TOUTES leurs versions historiques en une seule
# collection de metadonnees - un fichier de filelist (.solvx) de plus de
# 165 Mo a ete constate en reel, faisant ramer le solveur de dependances
# de dnf sur une VM modeste, meme pour un seul paquet deja precisement
# nomme. Probleme connu et documente publiquement du depot officiel
# Elastic lui-meme, pas un defaut de ce projet.
# Corrige : puisque FB_PACKAGE_VERSION est deja une version precise dans
# vars.conf (jamais "derniere version" en pratique sur ce projet), le
# RPM est telecharge DIRECTEMENT depuis l'URL de telechargement direct
# d'Elastic (artifacts.elastic.co/downloads/..., stable et documentee
# publiquement), puis installe localement - aucune resolution ni aucun
# solveur contre l'enorme catalogue combine. Repli automatique sur
# l'ancienne methode (depot + dnf) si le telechargement direct echoue
# (ex. FB_PACKAGE_VERSION vide, ou URL indisponible) - jamais un point
# unique de defaillance.
#
# CORRIGE UNE TROISIEME FOIS LE 2026-08-31 (meme jour, meme incident
# constate sur MB_004.sh - voir son en-tete) : "artifacts.elastic.co"
# souffre d'une resolution DNS INTERMITTENTE deja documentee
# (WAZ_010.sh) - un echec ponctuel de curl ne prouve pas que l'URL est
# reellement inaccessible. Le telechargement direct est desormais
# retente 3 fois (5s d'ecart) avant de ceder la place au depot lent.
set -uo pipefail
source "$VARS_FILE"

# CORRIGE LE 2026-08-12 (meme bug/correctif que ES_017) : verifier via
# le code de retour de "rpm -q", pas via le contenu de "--qf" qui peut
# porter un message localise "paquet absent" capture comme version.
if rpm -q filebeat &>/dev/null; then
  INSTALLED_VER=$(rpm -q --qf '%{VERSION}' filebeat 2>/dev/null)
  if [ -z "${FB_PACKAGE_VERSION:-}" ] || [ "$INSTALLED_VER" = "${FB_PACKAGE_VERSION}" ]; then
    echo "[FB_004] Paquet filebeat deja installe (version ${INSTALLED_VER}), ignore."
  else
    echo "[FB_004] AVERTISSEMENT : version installee (${INSTALLED_VER}) differente de FB_PACKAGE_VERSION (${FB_PACKAGE_VERSION}). Pas de changement automatique - desinstallez manuellement si besoin."
  fi
  echo "[FB_004] OK."
  exit 0
fi

INSTALLED=0
if [ -n "${FB_PACKAGE_VERSION:-}" ]; then
  RPM_URL="https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-${FB_PACKAGE_VERSION}-x86_64.rpm"
  RPM_LOCAL="${WORK_TMP_DIR}/filebeat-${FB_PACKAGE_VERSION}.rpm"
  echo "[FB_004] Telechargement direct de ${RPM_URL} (evite le solveur sur l'enorme depot combine Elastic)..."
  DOWNLOADED=0
  for essai in 1 2 3; do
    if curl -sf --connect-timeout 10 -o "$RPM_LOCAL" "$RPM_URL"; then
      DOWNLOADED=1
      break
    fi
    echo "[FB_004] AVERTISSEMENT : telechargement direct echoue (essai ${essai}/3, resolution DNS intermittente connue - voir WAZ_010.sh)..."
    [ "$essai" -lt 3 ] && sleep 5
  done
  if [ "$DOWNLOADED" -eq 1 ]; then
    echo "[FB_004] Installation locale du RPM telecharge..."
    if dnf install -y "$RPM_LOCAL"; then
      INSTALLED=1
    else
      echo "[FB_004] AVERTISSEMENT : installation du RPM local echouee, repli sur le depot."
    fi
    rm -f "$RPM_LOCAL"
  else
    echo "[FB_004] AVERTISSEMENT : telechargement direct echoue apres 3 essais, repli sur le depot."
  fi
fi

if [ "$INSTALLED" -ne 1 ]; then
  PKG_SPEC="filebeat${FB_PACKAGE_VERSION:+-${FB_PACKAGE_VERSION}}"
  echo "[FB_004] Installation du paquet ${PKG_SPEC} via le depot (peut etre lent, gros catalogue combine Elastic)..."
  if ! dnf install -y "$PKG_SPEC"; then
    echo "[FB_004] AVERTISSEMENT : dnf install a echoue, nouvel essai en forcant l'IPv4 (--setopt=ip_resolve=4)..."
    if ! dnf install -y --setopt=ip_resolve=4 "$PKG_SPEC"; then
      echo "[FB_004] ERREUR : dnf install a echoue meme en IPv4 force." >&2
      exit 1
    fi
  fi
fi

if ! rpm -q filebeat &>/dev/null; then
  echo "[FB_004] ERREUR : filebeat n'est toujours pas installe (verification rpm -q)." >&2
  exit 1
fi
echo "[FB_004] OK."
exit 0
