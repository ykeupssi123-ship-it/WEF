#!/bin/bash
# ES_014 - WEF_ES_BLD_FWOPEN9300 - Ouverture du port 9300 (transport)
#
# CORRIGE LE 2026-08-31 - meme diagnostic reel que ES_013.sh (voir son
# en-tete) : "IngestionZone" jamais liee a une interface, sans impact
# fonctionnel aujourd'hui vu l'isolation deliberee sur 127.0.0.1
# (ES_023.sh), corrige par coherence en ciblant "public".
set -uo pipefail
source "$VARS_FILE"
echo "[ES_014] Ouverture du port ${ES_TRANSPORT_PORT}/tcp sur public..."
firewall-cmd --permanent --zone=public --add-port=${ES_TRANSPORT_PORT}/tcp
firewall-cmd --reload
echo "[ES_014] OK."
exit 0
