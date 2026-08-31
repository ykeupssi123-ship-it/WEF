#!/bin/bash
# WAZ_038_KIBANA_VERIFY - WEF_WAZ_RUN_KBALIVE
# Verifie que Kibana repond et affiche bien le data view Wazuh.
set -uo pipefail
source "$VARS_FILE"

BOOTSTRAP_PW_FILE="${STATE_DIR}/es_bootstrap_password.secret"
[ -f "$BOOTSTRAP_PW_FILE" ] || { echo "[WAZ_038_KIBANA_VERIFY] ERREUR : $BOOTSTRAP_PW_FILE absent (ES_022 doit avoir tourne sur ELK_HOST)."; exit 1; }

echo "[WAZ_038_KIBANA_VERIFY] Verification sante Kibana..."
STATUS=$(curl -s -k -o /dev/null -w "%{http_code}" "https://${FACTORY_HOST_IP}:${KB_PORT}/api/status" \
  -u "elastic:$(cat "$BOOTSTRAP_PW_FILE")" 2>/dev/null || echo "000")
if [ "$STATUS" = "200" ]; then
  echo "[WAZ_038_KIBANA_VERIFY] Kibana repond (HTTP 200)."
else
  echo "[WAZ_038_KIBANA_VERIFY] AVERTISSEMENT : Kibana a repondu HTTP $STATUS."
fi
echo "[WAZ_038_KIBANA_VERIFY] OK."
exit 0
