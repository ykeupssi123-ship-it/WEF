#!/bin/bash
# WAZ_032 - WEF_WAZ_BLD_IMMTBLBASE - Verrouillage des fichiers fondamentaux
set -uo pipefail
source "$VARS_FILE"
echo "[WAZ_032] Verrouillage immuable des fichiers de securite de base..."
chattr +i /etc/wazuh-indexer/wazuh-indexer.yml /var/ossec/etc/ossec.conf 2>/dev/null || true
echo "[WAZ_032] OK."
exit 0
