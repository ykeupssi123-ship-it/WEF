#!/bin/bash
# LS_022 - WEF_LS_RUN_FILTERMASKPWD - Suppression des mots de passe en clair
set -uo pipefail
source "$VARS_FILE"
if grep -qF 'password=[MASKED]' /etc/logstash/conf.d/10-privacy-filter.conf 2>/dev/null; then
  echo "[LS_022] Filtre de masquage deja present, ignore."
  echo "[LS_022] OK."
  exit 0
fi
echo "[LS_022] Ajout du filtre de masquage mot de passe..."
cat >> /etc/logstash/conf.d/10-privacy-filter.conf << 'CONFEOF'
filter {
  mutate {
    gsub => [ "message", "password=\S+", "password=[MASKED]" ]
  }
}
CONFEOF
echo "[LS_022] OK."
exit 0
