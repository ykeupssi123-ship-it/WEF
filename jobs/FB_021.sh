#!/bin/bash
# FB_021 - WEF_FB_BLD_PERMLOCK - Droits stricts sur le keystore et le YML
set -uo pipefail
source "$VARS_FILE"
echo "[FB_021] Verrouillage des permissions..."
chmod 600 /etc/filebeat/filebeat.yml /var/lib/filebeat/registry -R
echo "[FB_021] OK."
exit 0
