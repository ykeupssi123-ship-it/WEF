#!/bin/bash
# FB_003 - WEF_FB_BLD_REPOSET - Depot officiel Filebeat
set -uo pipefail
source "$VARS_FILE"
echo "[FB_003] Ecriture du depot filebeat..."
cat > /etc/yum.repos.d/filebeat.repo << REPOEOF
[filebeat]
name=Elastic repository for Filebeat
baseurl=https://artifacts.elastic.co/packages/${ELASTIC_STACK_REPO_MAJOR}/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md
REPOEOF
echo "[FB_003] OK."
exit 0
