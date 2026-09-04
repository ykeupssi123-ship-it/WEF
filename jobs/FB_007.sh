#!/bin/bash
# FB_007 - WEF_FB_BLD_INPUTGNRC - Entrees de tracabilite de l'hote
set -uo pipefail
source "$VARS_FILE"
echo "[FB_007] Configuration des entrees locales..."
cat > /etc/filebeat/prospectors.d/local_logs.yml << CONFEOF
- type: log
  enabled: true
  paths:
    - /var/log/*.log
    - /var/log/messages
CONFEOF
grep -q "^filebeat.config.inputs.path:" /etc/filebeat/filebeat.yml 2>/dev/null || \
  echo 'filebeat.config.inputs.path: ${path.config}/prospectors.d/*.yml' >> /etc/filebeat/filebeat.yml
echo "[FB_007] OK."
exit 0
