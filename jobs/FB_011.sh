#!/bin/bash
# FB_011 - WEF_FB_BLD_MEMBUF - Calibrage de la memoire tampon d'urgence
set -uo pipefail
source "$VARS_FILE"
echo "[FB_011] Calibrage de la queue memoire..."
grep -q "^queue.mem.events:" /etc/filebeat/filebeat.yml 2>/dev/null || echo "queue.mem.events: 4096" >> /etc/filebeat/filebeat.yml
echo "[FB_011] OK."
exit 0
