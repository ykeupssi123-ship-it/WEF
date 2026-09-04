#!/bin/bash
# ES_009 - WEF_ES_BLD_UTILSINSTLL - wget, unzip, policycoreutils uniquement
set -uo pipefail
source "$VARS_FILE"
echo "[ES_009] Installation des utilitaires manquants (JDK natif Elastic preserve)..."
for pkg in wget unzip policycoreutils; do
  rpm -q "$pkg" &>/dev/null || dnf install -y "$pkg"
done
echo "[ES_009] OK."
exit 0
