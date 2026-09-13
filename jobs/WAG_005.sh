#!/bin/bash
# WAG_005 - WEF_WAG_BLD_SVCSTART
# Active le demarrage automatique de wazuh-agent au boot et (re)demarre
# le service pour appliquer la configuration ecrite par WAG_004.
#
# CORRIGE LE 2026-09-13 (audit de conformite pre-deploiement VM2, avant
# meme un premier echec reel sur ce job precis - trouve par comparaison
# directe avec FB_014/MB_014, qui avaient deja appris cette lecon) :
# verification d'activite en un seul essai, apres un "sleep 3" fixe -
# meme classe de bug deja corrigee 4 fois cote ELK_HOST (WAZ_014/
# WAZ_020_VERIFY/WAZ_022/WAZ_037) : un service qui vient de (re)demarrer
# peut avoir besoin de quelques secondes de plus pour se stabiliser
# reellement, surtout sur une machine aux ressources serrees (VM2 reelle
# a 1 Go RAM). Corrige : boucle de reessai bornee (60 x 2s = 120s max),
# jamais un seul essai a froid.
set -uo pipefail
source "$VARS_FILE"

echo "[WAG_005] Activation et demarrage de wazuh-agent..."
systemctl daemon-reload
systemctl enable wazuh-agent
systemctl restart wazuh-agent

for i in $(seq 1 60); do
  if systemctl is-active --quiet wazuh-agent; then
    echo "[WAG_005] wazuh-agent actif."
    echo "[WAG_005] OK."
    exit 0
  fi
  sleep 2
done

echo "[WAG_005] ERREUR : wazuh-agent n'a pas demarre (120s ecoulees). Diagnostic (journalctl -u wazuh-agent -n 30) :"
journalctl -u wazuh-agent -n 30 --no-pager 2>/dev/null || true
exit 1
