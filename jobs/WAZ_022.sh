#!/bin/bash
# WAZ_022 - WEF_WAZ_BLD_APIKEYGEN - Token d'interconnexion API Wazuh
#
# MODIFIE LE 2026-08-30 : WAZ_API_PASSWORD vient desormais de
# WAZ_API_PASSWORD_FILE (jamais vars.conf en clair). Lu en LECTURE SEULE
# (generer=non) : contrairement a WAZ_INDEXER_ADMIN_PASSWORD, aucun job
# de cette usine ne pousse aujourd'hui ce mot de passe vers l'API Wazuh
# (wazuh-apid) - en generer un nouveau ici casserait l'authentification
# au lieu de la reparer. Limite honnete, a ne pas masquer : ce fichier
# doit deja contenir la valeur reellement configuree cote wazuh-apid
# (verifiee par test reel le 2026-08-30 : HTTP 200 confirme).
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

WAZ_API_PASSWORD="$(read_or_generate_secret "$WAZ_API_PASSWORD_FILE" non)" || exit 1

echo "[WAZ_022] Authentification aupres de l'API Wazuh..."
curl -s -u "${WAZ_API_USER}:${WAZ_API_PASSWORD}" -k \
  "https://127.0.0.1:${WAZ_API_PORT}/security/user/authenticate" -X POST -o ${WORK_TMP_DIR}/waz022.json
python3 -c "import json; d=json.load(open('${WORK_TMP_DIR}/waz022.json')); assert 'data' in d" \
  && { echo "[WAZ_022] OK."; rm -f ${WORK_TMP_DIR}/waz022.json; exit 0; }
echo "[WAZ_022] ERREUR, voir ${WORK_TMP_DIR}/waz022.json"; exit 1
