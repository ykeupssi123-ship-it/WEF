#!/bin/bash
# ES_016 - WEF_ES_BLD_REPOSET - Depot officiel Elasticsearch
set -uo pipefail
source "$VARS_FILE"
echo "[ES_016] Ecriture du depot elasticsearch.repo..."
cat > /etc/yum.repos.d/elasticsearch.repo << REPOEOF
[elasticsearch]
name=Elasticsearch repository
baseurl=https://artifacts.elastic.co/packages/${ELASTIC_STACK_REPO_MAJOR}/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md
REPOEOF
echo "[ES_016] OK."
exit 0
