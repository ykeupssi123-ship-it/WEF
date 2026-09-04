#!/bin/bash
# LS_010 - WEF_LS_BLD_REPOSET - Depot officiel Logstash
set -uo pipefail
source "$VARS_FILE"
echo "[LS_010] Ecriture du depot logstash.repo..."
cat > /etc/yum.repos.d/logstash.repo << REPOEOF
[logstash]
name=Elastic repository for Logstash
baseurl=https://artifacts.elastic.co/packages/${ELASTIC_STACK_REPO_MAJOR}/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md
REPOEOF
echo "[LS_010] OK."
exit 0
