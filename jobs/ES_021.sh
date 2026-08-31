#!/bin/bash
# ES_021 - WEF_ES_BLD_KSTINIT - Initialisation du keystore local
#
# CORRECTIF 2026-08-14 (audit systemique suite a l'incident LS_B025_ARMED) :
# "elasticsearch-keystore create" se declarait OK sans jamais verifier
# que le fichier avait reellement ete cree - meme famille de bug qui a
# fait planter Logstash en boucle sur VM1 (voir README, incident 17).
# Corrige : on verifie que le fichier existe reellement apres l'appel.
set -uo pipefail
source "$VARS_FILE"
if [ -f /etc/elasticsearch/elasticsearch.keystore ]; then
  echo "[ES_021] Keystore deja initialise, ignore."
  echo "[ES_021] OK."
  exit 0
fi
echo "[ES_021] Creation du keystore Elasticsearch..."
/usr/share/elasticsearch/bin/elasticsearch-keystore create
if [ ! -f /etc/elasticsearch/elasticsearch.keystore ]; then
  echo "[ES_021] ERREUR : /etc/elasticsearch/elasticsearch.keystore n'existe toujours pas apres 'elasticsearch-keystore create'." >&2
  exit 1
fi
echo "[ES_021] OK (fichier confirme present)."
exit 0
