#!/bin/bash
# MB_004 - WEF_MB_BLD_BININST - Installation du paquet Metricbeat
# Version pilotee par MB_PACKAGE_VERSION dans vars.conf (vide = derniere
# version disponible dans le depot ELASTIC_STACK_REPO_MAJOR). Ne change
# jamais une version deja en place, seulement au premier passage.
#
# CORRIGE LE 2026-08-31 (meme audit reel que FB_004.sh/WAG_003.sh, meme
# jour, premier deploiement d'agent sur 192.168.50.130) : "dnf install
# -y" jamais verifie - meme correctif (code de sortie dnf, repli IPv4,
# verification rpm -q apres coup).
#
# CORRIGE ENCORE LE 2026-08-31 (meme incident reel que FB_004.sh - voir
# son en-tete pour le diagnostic complet) : le depot combine Elastic
# fait ramer le solveur dnf (plus de 20 minutes constatees en reel pour
# filebeat seul). Meme remede : telechargement direct du RPM depuis
# artifacts.elastic.co/downloads/, repli sur le depot uniquement si
# indisponible.
#
# CORRIGE UNE TROISIEME FOIS LE 2026-08-31 (meme jour, incident reel :
# metricbeat a lui aussi bascule sur le depot lent, le telechargement
# direct ayant echoue en un seul essai) : "artifacts.elastic.co" souffre
# d'une resolution DNS INTERMITTENTE deja documentee (WAZ_010.sh) - un
# echec ponctuel de curl ne prouve pas que l'URL est reellement
# inaccessible, juste qu'UNE tentative a echoue au mauvais moment. Le
# repli immediat sur le depot (sans meme reessayer le telechargement
# direct, bien plus rapide) gaspillait donc des minutes reelles a
# chaque coincidence malheureuse. Corrige : le telechargement direct est
# desormais retente 3 fois (5s d'ecart) avant de ceder la place au
# depot.
set -uo pipefail
source "$VARS_FILE"

# CORRIGE LE 2026-08-12 (meme bug/correctif que ES_017) : verifier via
# le code de retour de "rpm -q", pas via le contenu de "--qf" qui peut
# porter un message localise "paquet absent" capture comme version.
if rpm -q metricbeat &>/dev/null; then
  INSTALLED_VER=$(rpm -q --qf '%{VERSION}' metricbeat 2>/dev/null)
  if [ -z "${MB_PACKAGE_VERSION:-}" ] || [ "$INSTALLED_VER" = "${MB_PACKAGE_VERSION}" ]; then
    echo "[MB_004] Paquet metricbeat deja installe (version ${INSTALLED_VER}), ignore."
  else
    echo "[MB_004] AVERTISSEMENT : version installee (${INSTALLED_VER}) differente de MB_PACKAGE_VERSION (${MB_PACKAGE_VERSION}). Pas de changement automatique - desinstallez manuellement si besoin."
  fi
  echo "[MB_004] OK."
  exit 0
fi

INSTALLED=0
if [ -n "${MB_PACKAGE_VERSION:-}" ]; then
  RPM_URL="https://artifacts.elastic.co/downloads/beats/metricbeat/metricbeat-${MB_PACKAGE_VERSION}-x86_64.rpm"
  RPM_LOCAL="${WORK_TMP_DIR}/metricbeat-${MB_PACKAGE_VERSION}.rpm"
  echo "[MB_004] Telechargement direct de ${RPM_URL} (evite le solveur sur l'enorme depot combine Elastic)..."
  DOWNLOADED=0
  for essai in 1 2 3; do
    if curl -sf --connect-timeout 10 -o "$RPM_LOCAL" "$RPM_URL"; then
      DOWNLOADED=1
      break
    fi
    echo "[MB_004] AVERTISSEMENT : telechargement direct echoue (essai ${essai}/3, resolution DNS intermittente connue - voir WAZ_010.sh)..."
    [ "$essai" -lt 3 ] && sleep 5
  done
  if [ "$DOWNLOADED" -eq 1 ]; then
    echo "[MB_004] Installation locale du RPM telecharge..."
    if dnf install -y "$RPM_LOCAL"; then
      INSTALLED=1
    else
      echo "[MB_004] AVERTISSEMENT : installation du RPM local echouee, repli sur le depot."
    fi
    rm -f "$RPM_LOCAL"
  else
    echo "[MB_004] AVERTISSEMENT : telechargement direct echoue apres 3 essais, repli sur le depot."
  fi
fi

if [ "$INSTALLED" -ne 1 ]; then
  PKG_SPEC="metricbeat${MB_PACKAGE_VERSION:+-${MB_PACKAGE_VERSION}}"
  echo "[MB_004] Installation du paquet ${PKG_SPEC} via le depot (peut etre lent, gros catalogue combine Elastic)..."
  if ! dnf install -y "$PKG_SPEC"; then
    echo "[MB_004] AVERTISSEMENT : dnf install a echoue, nouvel essai en forcant l'IPv4 (--setopt=ip_resolve=4)..."
    if ! dnf install -y --setopt=ip_resolve=4 "$PKG_SPEC"; then
      echo "[MB_004] ERREUR : dnf install a echoue meme en IPv4 force." >&2
      exit 1
    fi
  fi
fi

if ! rpm -q metricbeat &>/dev/null; then
  echo "[MB_004] ERREUR : metricbeat n'est toujours pas installe (verification rpm -q)." >&2
  exit 1
fi
echo "[MB_004] OK."
exit 0
