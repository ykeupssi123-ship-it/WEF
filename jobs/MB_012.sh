#!/bin/bash
# MB_012 - WEF_MB_BLD_OUTGLB - Liaison de sortie vers Logstash
# CORRECTIF 2-VM : FACTORY_HOST_IP au lieu de 127.0.0.1 (meme raison que FB_012).
#
# SUPPRIME LE 2026-08-31 : MB_009/MB_010 (coffre de secrets Metricbeat)
# retires - meme diagnostic reel que FB_012.sh (voir son en-tete) :
# "output.logstash" ci-dessous n'a jamais besoin d'identifiants, deux
# jobs entierement morts.
#
# CORRIGE LE 2026-08-31 (meme incident reel que FB_012.sh, memes deux
# sections indissociables : anticipe ici avant meme sa premiere
# execution sur un metricbeat.yml de paquet, la structure par defaut
# etant partagee entre les produits Beats) : neutralisation du bloc
# output.elasticsearch actif AVANT d'ajouter output.logstash - voir
# l'en-tete de FB_012.sh pour le diagnostic complet.
set -uo pipefail
source "$VARS_FILE"
[ -n "${FACTORY_HOST_IP:-}" ] || { echo "[MB_012] ERREUR : FACTORY_HOST_IP vide dans vars.conf."; exit 1; }

if grep -q "^output\.elasticsearch:" /etc/metricbeat/metricbeat.yml 2>/dev/null; then
  echo "[MB_012] Neutralisation du bloc output.elasticsearch actif (paquet par defaut, incompatible avec output.logstash)..."
  awk '
    /^output\.elasticsearch:/ { inblock=1; print "#" $0; next }
    inblock && (/^[[:space:]]/ || /^[[:space:]]*$/) { print "#" $0; next }
    { inblock=0; print }
  ' /etc/metricbeat/metricbeat.yml > /etc/metricbeat/metricbeat.yml.wef_tmp && mv /etc/metricbeat/metricbeat.yml.wef_tmp /etc/metricbeat/metricbeat.yml
fi

if grep -q "^output.logstash:" /etc/metricbeat/metricbeat.yml 2>/dev/null; then
  echo "[MB_012] Sortie Logstash deja configuree, ignore."
  echo "[MB_012] OK."
  exit 0
fi
echo "[MB_012] Configuration de la sortie vers Logstash (${FACTORY_HOST_IP}:${LS_BEATS_PORT})..."
cat >> /etc/metricbeat/metricbeat.yml << YMLEOF
output.logstash:
  hosts: ["${FACTORY_HOST_IP}:${LS_BEATS_PORT}"]
  ssl.certificate_authorities: ["${PKI_DIR}/factory_ca.crt"]
YMLEOF
echo "[MB_012] OK."
exit 0
