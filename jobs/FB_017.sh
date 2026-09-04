#!/bin/bash
# FB_017 - WEF_FB_RUN_RGSTRYCHECK - Validation du pointeur de lecture local
#
# CORRIGE LE 2026-08-31 (meme audit reel que FB_014.sh, meme jour) :
# "data.json" est un nom de fichier obsolete (anciennes versions de
# Filebeat) - confirme en reel (find /var/lib/filebeat) que la version
# installee (8.19.14) ecrit le registre sous "log.json", jamais
# "data.json".
set -uo pipefail
source "$VARS_FILE"
echo "[FB_017] Verification du registre Filebeat..."
[ -f /var/lib/filebeat/registry/filebeat/log.json ] || { echo "[FB_017] ERREUR : registre absent (/var/lib/filebeat/registry/filebeat/log.json)."; exit 1; }
echo "[FB_017] OK."
exit 0
