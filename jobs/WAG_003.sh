#!/bin/bash
# WAG_003 - WEF_WAG_BLD_BININST - Installation de wazuh-agent
# Version pilotee par WAZ_AGENT_PACKAGE_VERSION dans vars.conf (vide =
# derniere version du depot). Comme les autres jobs d'installation du
# projet, ne change jamais une version deja en place - seulement au
# premier passage. WAZUH_MANAGER/WAZUH_AGENT_NAME sont pre-configures
# au moment de l'installation (mecanisme officiel Wazuh), repris et
# confirmes ensuite par WAG_004.
#
# CORRIGE LE 2026-08-31 (incident reel, premier deploiement d'agent sur
# 192.168.50.130) : "dnf install -y" n'etait jamais verifie - meme classe
# de bug deja trouvee et corrigee ailleurs dans cette usine (WAZ_010/
# WAZ_012/DNS_001), jamais appliquee ici jusqu'a ce premier deploiement
# reel d'agent. Constate en reel : le depot flottant "filebeat" (installe
# par un autre composant AGENT_COMPONENTS sur la meme machine) a echoue
# sa resolution DNS ("Could not resolve host: artifacts.elastic.co",
# incident IPv6/DNS deja documente dans WAZ_010.sh) PENDANT le
# rafraichissement des metadonnees dnf declenche par cette installation -
# dnf a echoue globalement, wazuh-agent n'a jamais ete installe, mais ce
# job a quand meme affiche "OK" (aucune verification apres coup) :
# WAG_004 a echoue juste apres sur "/var/ossec/etc/ossec.conf introuvable"
# - le vrai symptome trouve bien plus tard que la vraie cause. Corrige :
# code de sortie dnf verifie, repli IPv4 (--setopt=ip_resolve=4, meme
# incident reseau connu que WAZ_010), puis presence reelle confirmee via
# rpm -q apres coup - jamais un "OK" qui ne repose que sur l'absence
# d'exception shell.
set -uo pipefail
source "$VARS_FILE"

if [ -z "${AGENT_NAME:-}" ]; then
  echo "[WAG_003] ERREUR : AGENT_NAME est vide dans vars.conf. Donnez un nom unique a cet agent avant d'installer."
  exit 1
fi

export WAZUH_MANAGER="${FACTORY_HOST_IP}"
export WAZUH_AGENT_NAME="${AGENT_NAME}"

if command -v rpm >/dev/null 2>&1; then
  # CORRIGE LE 2026-08-12 (meme bug/correctif que ES_017) : verifier via
  # le code de retour de "rpm -q", pas via le contenu de "--qf" qui peut
  # porter un message localise "paquet absent" capture comme version.
  if rpm -q wazuh-agent &>/dev/null; then
    INSTALLED_VER=$(rpm -q --qf '%{VERSION}' wazuh-agent 2>/dev/null)
    if [ -z "${WAZ_AGENT_PACKAGE_VERSION:-}" ] || [ "$INSTALLED_VER" = "${WAZ_AGENT_PACKAGE_VERSION}" ]; then
      echo "[WAG_003] wazuh-agent deja installe (version ${INSTALLED_VER}), ignore."
    else
      echo "[WAG_003] AVERTISSEMENT : version installee (${INSTALLED_VER}) differente de WAZ_AGENT_PACKAGE_VERSION (${WAZ_AGENT_PACKAGE_VERSION}). Pas de changement automatique."
    fi
    echo "[WAG_003] OK."
    exit 0
  fi
  PKG_SPEC="wazuh-agent${WAZ_AGENT_PACKAGE_VERSION:+-${WAZ_AGENT_PACKAGE_VERSION}}"
  echo "[WAG_003] Installation de ${PKG_SPEC} (dnf/rpm)..."
  if ! dnf install -y "$PKG_SPEC"; then
    echo "[WAG_003] AVERTISSEMENT : dnf install a echoue, nouvel essai en forcant l'IPv4 (--setopt=ip_resolve=4, cas connu : IPv6/DNS casse sur certains reseaux, voir WAZ_010.sh)..."
    if ! dnf install -y --setopt=ip_resolve=4 "$PKG_SPEC"; then
      echo "[WAG_003] ERREUR : dnf install a echoue meme en IPv4 force (voir le message dnf ci-dessus)." >&2
      exit 1
    fi
  fi
  if ! rpm -q wazuh-agent &>/dev/null; then
    echo "[WAG_003] ERREUR : dnf s'est termine sans erreur mais wazuh-agent n'est toujours pas installe (verification rpm -q)." >&2
    exit 1
  fi
elif command -v apt-get >/dev/null 2>&1; then
  if dpkg -s wazuh-agent >/dev/null 2>&1; then
    INSTALLED_VER=$(dpkg-query -W -f='${Version}' wazuh-agent 2>/dev/null || echo "")
    if [ -z "${WAZ_AGENT_PACKAGE_VERSION:-}" ] || [ "$INSTALLED_VER" = "${WAZ_AGENT_PACKAGE_VERSION}" ]; then
      echo "[WAG_003] wazuh-agent deja installe (version ${INSTALLED_VER}), ignore."
    else
      echo "[WAG_003] AVERTISSEMENT : version installee (${INSTALLED_VER}) differente de WAZ_AGENT_PACKAGE_VERSION (${WAZ_AGENT_PACKAGE_VERSION}). Pas de changement automatique."
    fi
    echo "[WAG_003] OK."
    exit 0
  fi
  PKG_SPEC="wazuh-agent${WAZ_AGENT_PACKAGE_VERSION:+=${WAZ_AGENT_PACKAGE_VERSION}}"
  echo "[WAG_003] Installation de ${PKG_SPEC} (apt-get)..."
  apt-get install -y "$PKG_SPEC"
else
  echo "[WAG_003] ERREUR : gestionnaire de paquets non supporte."
  exit 1
fi

echo "[WAG_003] OK."
exit 0
