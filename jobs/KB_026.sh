#!/bin/bash
# KB_026 - WEF_KB_RUN_IMPORTDATA - Injection a chaud de configurations
#
# CORRECTIF 2026-08-19 (meme incident/meme audit que KB_025, wef-elk-core) :
# meme lacune - appel a l'API Kibana sans aucune authentification, alors
# que la securite est active depuis le debut du projet. Corrige avec le
# meme identifiant que KB_025 (utilisateur elastic, mot de passe
# bootstrap).
set -uo pipefail
source "$VARS_FILE"
BOOTSTRAP_PW_FILE="${STATE_DIR}/es_bootstrap_password.secret"
[ -f "$BOOTSTRAP_PW_FILE" ] || { echo "[KB_026] ERREUR : mot de passe bootstrap introuvable (ES_022 doit avoir tourne)."; exit 1; }
BOOTSTRAP_PW="$(cat "$BOOTSTRAP_PW_FILE")"
IMPORT_FILE="${STATE_DIR}/kibana_saved_objects_export.ndjson"
if [ ! -s "$IMPORT_FILE" ]; then
  echo "[KB_026] Aucun fichier a importer (${IMPORT_FILE} vide ou absent), ignore."
  echo "[KB_026] OK."
  exit 0
fi
echo "[KB_026] Reimport des Saved Objects (validation d'adaptabilite)..."
curl -sk -u "elastic:${BOOTSTRAP_PW}" -H "kbn-xsrf: true" "https://127.0.0.1:${KB_PORT}/api/saved_objects/_import?overwrite=true" \
  -F "file=@${IMPORT_FILE}" -o ${WORK_TMP_DIR}/kb026.json
grep -q '"success":true' ${WORK_TMP_DIR}/kb026.json && { echo "[KB_026] OK."; rm -f ${WORK_TMP_DIR}/kb026.json; exit 0; }
echo "[KB_026] ERREUR, voir ${WORK_TMP_DIR}/kb026.json"; exit 1
