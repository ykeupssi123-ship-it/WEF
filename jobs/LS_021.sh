#!/bin/bash
# LS_021 - WEF_LS_RUN_FILTERMASKPCI - Anonymisation des cartes bancaires
set -uo pipefail
source "$VARS_FILE"
echo "[LS_021] Ecriture du filtre PCI-DSS..."
mkdir -p /etc/logstash/conf.d
cat > /etc/logstash/conf.d/10-privacy-filter.conf << 'CONFEOF'
filter {
  mutate {
    gsub => [ "message", "\b(?:\d[ -]*?){13,16}\b", "[MASKED_PAN]" ]
  }
}
CONFEOF
echo "[LS_021] OK."
exit 0
