#!/bin/bash
# WAZ_009 - WEF_WAZ_BLD_REPOSET - Depot officiel certifie Wazuh
set -uo pipefail
source "$VARS_FILE"
echo "[WAZ_009] Import de la cle GPG et ecriture du depot Wazuh..."
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
echo "[WAZ_009] OK."
exit 0
