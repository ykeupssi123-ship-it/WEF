#!/bin/bash
# WAZ_014D_ALERTS_RETENTION - WEF_WAZ_BLD_ALERTSRETAIN - Politique de
# cycle de vie (ISM) pour purger wazuh-alerts-4.x-*/wazuh-archives-4.x-*
#
# AJOUTE LE 2026-08-31 (point #9 de la mission : jobs d'exploitation
# continue, proposes une fois l'infrastructure stable). Sans politique
# de purge, l'index quotidien grossit indefiniment - meme classe de
# risque reel deja rencontree aujourd'hui (incidents disque plein
# pendant l'orchestrateur, voir INFRA_003_DEVNULL_GUARDIAN.sh). Utilise
# ISM (Index State Management), l'equivalent OpenSearch de l'ILM deja
# utilise cote Elasticsearch classique par ES_063_SNAPSHOTPOLICY - meme
# principe de "purge automatique passe un age donne", mecanisme natif
# du moteur (pas un timer + script externe comme les gardes INFRA_00x) :
# une fois posee, la politique s'applique EN PERMANENCE sans qu'aucun
# processus externe ne doive tourner.
#
# ORDRE : ce job depend de WAZ_ALERTS_TEMPLATE_OK (comme WAZ_014B) - la
# politique doit exister avant que de nouveaux index quotidiens ne se
# creent pour s'appliquer automatiquement des le depart via
# "ism_template". L'index du jour deja cree AVANT ce job (le tout
# premier jour de deploiement) recoit la politique explicitement via
# l'appel _ism/add ci-dessous, pour ne pas dependre uniquement du futur.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

WAZUH_INDEXER_ADMIN_PW="$(read_or_generate_secret "$WAZ_INDEXER_ADMIN_PASSWORD_FILE" non)" || exit 1
WAZ_INDEXER_PORT="${WAZ_INDEXER_PORT:-9200}"
RETENTION_DAYS="${WAZ_ALERTS_RETENTION_DAYS:-30}"
POLICY_ID="wef_alerts_retention"
AUTH=(-u "${WAZ_INDEXER_ADMIN_USER}:${WAZUH_INDEXER_ADMIN_PW}")

echo "[WAZ_014D] Pose de la politique ISM '${POLICY_ID}' (purge apres ${RETENTION_DAYS}j)..."
POLICY_JSON=$(cat << JSONEOF
{
  "policy": {
    "description": "Purge automatique des alertes Wazuh apres ${RETENTION_DAYS} jours (WAZ_014D_ALERTS_RETENTION)",
    "default_state": "hot",
    "states": [
      {
        "name": "hot",
        "actions": [],
        "transitions": [
          { "state_name": "delete", "conditions": { "min_index_age": "${RETENTION_DAYS}d" } }
        ]
      },
      {
        "name": "delete",
        "actions": [ { "delete": {} } ],
        "transitions": []
      }
    ],
    "ism_template": {
      "index_patterns": ["wazuh-alerts-4.x-*", "wazuh-archives-4.x-*"],
      "priority": 100
    }
  }
}
JSONEOF
)

HTTP_CODE=$(curl -sk "${AUTH[@]}" -X PUT "https://127.0.0.1:${WAZ_INDEXER_PORT}/_plugins/_ism/policies/${POLICY_ID}" \
  -H 'Content-Type: application/json' -d "$POLICY_JSON" \
  -o "${WORK_TMP_DIR}/waz014d_policy.json" -w '%{http_code}')

# Idempotence : un PUT sur une politique deja existante echoue en 409
# (conflit de version de document) - il faut alors recuperer sa
# _seq_no/_primary_term actuelle et les fournir pour la mettre a jour,
# plutot que de tenter une creation aveugle a chaque passage.
if [ "$HTTP_CODE" = "409" ]; then
  echo "[WAZ_014D] Politique deja existante, mise a jour (seq_no/primary_term actuels)..."
  CURRENT=$(curl -sk "${AUTH[@]}" "https://127.0.0.1:${WAZ_INDEXER_PORT}/_plugins/_ism/policies/${POLICY_ID}")
  SEQ_NO=$(echo "$CURRENT" | python3 -c "import json,sys; print(json.load(sys.stdin)['_seq_no'])" 2>/dev/null)
  PRIMARY_TERM=$(echo "$CURRENT" | python3 -c "import json,sys; print(json.load(sys.stdin)['_primary_term'])" 2>/dev/null)
  HTTP_CODE=$(curl -sk "${AUTH[@]}" -X PUT "https://127.0.0.1:${WAZ_INDEXER_PORT}/_plugins/_ism/policies/${POLICY_ID}?if_seq_no=${SEQ_NO}&if_primary_term=${PRIMARY_TERM}" \
    -H 'Content-Type: application/json' -d "$POLICY_JSON" \
    -o "${WORK_TMP_DIR}/waz014d_policy.json" -w '%{http_code}')
fi

if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ]; then
  echo "[WAZ_014D] ERREUR : pose de la politique ISM en echec (HTTP ${HTTP_CODE}), voir ${WORK_TMP_DIR}/waz014d_policy.json" >&2
  cat "${WORK_TMP_DIR}/waz014d_policy.json" >&2 2>/dev/null || true
  exit 1
fi

echo "[WAZ_014D] Application explicite aux index deja existants (ne depend pas uniquement des futurs index)..."
curl -sk "${AUTH[@]}" -X POST "https://127.0.0.1:${WAZ_INDEXER_PORT}/_plugins/_ism/add/wazuh-alerts-4.x-*,wazuh-archives-4.x-*" \
  -H 'Content-Type: application/json' -d "{\"policy_id\": \"${POLICY_ID}\"}" \
  -o "${WORK_TMP_DIR}/waz014d_add.json" -w '' || true

echo "[WAZ_014D] Verification reelle (la politique doit exister)..."
if ! curl -sk "${AUTH[@]}" "https://127.0.0.1:${WAZ_INDEXER_PORT}/_plugins/_ism/policies/${POLICY_ID}" | grep -q "\"policy_id\":\"${POLICY_ID}\""; then
  echo "[WAZ_014D] ERREUR : la politique '${POLICY_ID}' n'est pas confirmee presente apres la pose." >&2
  exit 1
fi

rm -f "${WORK_TMP_DIR}/waz014d_policy.json" "${WORK_TMP_DIR}/waz014d_add.json"
echo "[WAZ_014D] OK (politique '${POLICY_ID}' active, retention ${RETENTION_DAYS}j)."
exit 0
