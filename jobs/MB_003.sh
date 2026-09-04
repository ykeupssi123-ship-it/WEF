#!/bin/bash
# MB_003 - WEF_MB_BLD_REPOSET - Depot officiel Metricbeat
set -uo pipefail
source "$VARS_FILE"
echo "[MB_003] Ecriture du depot metricbeat..."
cat > /etc/yum.repos.d/metricbeat.repo << REPOEOF
[metricbeat]
name=Elastic repository for Metricbeat
baseurl=https://artifacts.elastic.co/packages/${ELASTIC_STACK_REPO_MAJOR}/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md
REPOEOF
echo "[MB_003] OK."
exit 0
