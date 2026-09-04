#!/bin/bash
# KB_004 - WEF_KB_BLD_REPOSET - Depot officiel Kibana
set -uo pipefail
source "$VARS_FILE"
echo "[KB_004] Ecriture du depot kibana.repo..."
cat > /etc/yum.repos.d/kibana.repo << REPOEOF
[kibana]
name=Kibana repository
baseurl=https://artifacts.elastic.co/packages/${ELASTIC_STACK_REPO_MAJOR}/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md
REPOEOF
echo "[KB_004] OK."
exit 0
