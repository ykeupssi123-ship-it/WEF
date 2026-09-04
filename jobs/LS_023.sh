#!/bin/bash
# LS_023 - WEF_LS_RUN_FILTERGEOIP - Enrichissement GeoIP
set -uo pipefail
source "$VARS_FILE"
echo "[LS_023] Ecriture du filtre d'enrichissement GeoIP..."
mkdir -p /etc/logstash/conf.d
cat > /etc/logstash/conf.d/11-enrichment.conf << 'CONFEOF'
filter {
  if [source_ip] {
    geoip {
      source => "source_ip"
      target => "geoip"
    }
  }
}
CONFEOF
echo "[LS_023] OK."
exit 0
