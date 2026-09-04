#!/bin/bash
# WAZ_013 - WEF_WAZ_BLD_CONFAMVBL - Initialisation boucle locale stricte
set -uo pipefail
source "$VARS_FILE"
echo "[WAZ_013] Ecriture de la configuration initiale ossec.conf (boucle locale)..."
if ! grep -q "<jsonout_output>" /var/ossec/etc/ossec.conf 2>/dev/null; then
  sed -i '/<\/ossec_config>/i\
  <syslog_output>\
    <disabled>yes</disabled>\
  </syslog_output>\
  <jsonout_output>\
    <enabled>yes</enabled>\
  </jsonout_output>' /var/ossec/etc/ossec.conf
fi
echo "[WAZ_013] OK."
exit 0
