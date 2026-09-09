#!/bin/bash
# WAZ_006B_FW_DASHAPI - WEF_WAZ_BLD_FWDASHAPI - Ouverture des ports
# Wazuh Dashboard (443) et Wazuh API (55000)
#
# AJOUTE LE 2026-09-09 (incident reel, VM neuve : Wazuh Dashboard
# injoignable depuis un navigateur externe, ERR_CONNECTION_TIMED_OUT sur
# https://<ip>:443/, alors que le tableau de bord final affichait cette
# URL comme prete a l'emploi). Cause racine reelle, trouvee en relisant
# l'historique de ce meme type d'incident deja rencontre et corrige le
# 2026-08-31 (voir en-tetes de WAZ_005.sh/WAZ_006.sh/KB_007.sh) : ces
# 3 jobs documentent explicitement que 443 (Dashboard) et 55000 (API)
# etaient PRESUMES "deja ouverts par coincidence, via le post-install du
# paquet RPM" - exactement la meme hypothese non verifiee qui s'est deja
# revelee fausse pour 1514/1515 (WAZ_005) et 9200/9300 (WAZ_006) ce
# jour-la. Ces deux ports precis (443/55000) n'avaient cependant jamais
# recu leur propre job dedie, contrairement a tous les autres deja
# corriges - angle mort reel, jamais teste depuis un vrai navigateur
# externe jusqu'a aujourd'hui. Corrige en ciblant "public" (la SEULE
# zone reellement liee a l'interface reseau reelle, meme diagnostic que
# WAZ_005/WAZ_006/ES_013/ES_014/KB_007 - "internal"/"UI_Zone" ne sont
# jamais liees a une interface, donc invisibles au trafic reel).
set -uo pipefail
source "$VARS_FILE"
echo "[WAZ_006B_FW_DASHAPI] Ouverture des ports ${WAZ_DASH_PORT} (Wazuh Dashboard) et ${WAZ_API_PORT} (Wazuh API) sur public..."
firewall-cmd --permanent --zone=public --add-port=${WAZ_DASH_PORT}/tcp
firewall-cmd --permanent --zone=public --add-port=${WAZ_API_PORT}/tcp
firewall-cmd --reload
echo "[WAZ_006B_FW_DASHAPI] OK."
exit 0
