#!/bin/bash
# KB_017 - WEF_KB_BLD_KSTINIT - Initialisation du coffre de secrets
#
# CORRECTIF 2026-08-14 (audit systemique suite a l'incident LS_B025_ARMED) :
# "kibana-keystore create" se declarait OK sans jamais verifier que le
# fichier avait reellement ete cree - meme famille de bug qui a fait
# planter Logstash en boucle sur VM1 (voir README, incident 17).
set -uo pipefail
source "$VARS_FILE"
if [ -f /etc/kibana/kibana.keystore ]; then
  echo "[KB_017] Keystore deja initialise, ignore."
  echo "[KB_017] OK."
  exit 0
fi
echo "[KB_017] Creation du keystore Kibana..."
/usr/share/kibana/bin/kibana-keystore create
if [ ! -f /etc/kibana/kibana.keystore ]; then
  echo "[KB_017] ERREUR : /etc/kibana/kibana.keystore n'existe toujours pas apres 'kibana-keystore create'." >&2
  exit 1
fi
echo "[KB_017] OK (fichier confirme present)."
exit 0
