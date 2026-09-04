#!/bin/bash
# WAG_002 - WEF_WAG_BLD_REPOSET - Depot officiel Wazuh (agent)
# Meme depot que le manager (WAZUH_REPO_MAJOR), duplique ici car cet
# hote est une machine differente de VM1/VM2.
set -uo pipefail
source "$VARS_FILE"

echo "[WAG_002] Ecriture du depot Wazuh..."
if command -v rpm >/dev/null 2>&1; then
  if [ ! -f /etc/yum.repos.d/wazuh.repo ]; then
    rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH
    cat > /etc/yum.repos.d/wazuh.repo << REPOEOF
[wazuh]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
name=EL-\$releasever - Wazuh
baseurl=https://packages.wazuh.com/${WAZUH_REPO_MAJOR}/yum/
protect=1
REPOEOF
  else
    echo "[WAG_002] Depot RPM Wazuh deja present."
  fi
elif command -v apt-get >/dev/null 2>&1; then
  if [ ! -f /etc/apt/sources.list.d/wazuh.list ]; then
    curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import
    chmod 644 /usr/share/keyrings/wazuh.gpg
    echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/${WAZUH_REPO_MAJOR}/apt/ stable main" > /etc/apt/sources.list.d/wazuh.list
    apt-get update -y
  else
    echo "[WAG_002] Depot APT Wazuh deja present."
  fi
else
  echo "[WAG_002] ERREUR : gestionnaire de paquets non supporte (ni rpm ni apt-get)."
  exit 1
fi

echo "[WAG_002] OK."
exit 0
