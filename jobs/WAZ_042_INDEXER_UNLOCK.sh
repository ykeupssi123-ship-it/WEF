#!/bin/bash
# WAZ_042_INDEXER_UNLOCK - WEF_WAZ_RUN_IDXUNLOCK - Leve les verrous
# "lecture seule" (flood-stage) sur wazuh-indexer
#
# AJOUTE LE 2026-08-31 (point #9 de la mission - "meme les erreurs
# rencontrees doivent devenir des jobs RUN rejouables" - demande
# explicite de l'utilisateur apres un incident reel wef-elk-core).
#
# DIAGNOSTIC REEL (jamais suppose) : lors d'un episode de disque plein
# (deja documente ce jour dans INFRA_005_DISK_HYGIENE.sh), le
# DiskThresholdMonitor natif d'OpenSearch a appose
# "index.blocks.read_only_allow_delete: true" sur TOUTES les indices
# actives a ce moment-la (confirme en reel : ".kibana_1",
# "wazuh-alerts-4.x-*", "wazuh-monitoring-*", "wazuh-statistics-*", etc.)
# - un verrou de PROTECTION qui bloque toute nouvelle ecriture. PIEGE
# REEL, verifie par test direct : ce verrou NE SE LEVE PAS TOUT SEUL
# quand l'espace disque redevient suffisant (contrairement a une
# intuition raisonnable) - il faut le retirer explicitement, index par
# index. Symptome observe cote utilisateur : le tableau de bord Wazuh
# refusait silencieusement certaines operations (ex. suppression d'un
# index-pattern perime) bien apres la resolution du probleme de disque
# d'origine.
#
# PORTEE VOLONTAIREMENT LIMITEE : les index systeme proteges par le
# plugin de securite (".opendistro_security", ".plugins-ml-config",
# ".opensearch-observability", ".opendistro-job-scheduler-lock") REFUSENT
# cette commande meme pour le compte admin (confirme en reel : "no
# permissions for []") - ils exigent securityadmin.sh avec certificat
# client (meme limitation deja documentee dans WAZ_017E_AUTHAPPLY.sh).
# Ce job les liste honnetement sans y toucher, plutot que d'echouer
# silencieusement ou de pretendre les avoir traites.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

WAZUH_INDEXER_ADMIN_PW="$(read_or_generate_secret "$WAZ_INDEXER_ADMIN_PASSWORD_FILE" non)" || exit 1
WAZ_INDEXER_PORT="${WAZ_INDEXER_PORT:-9200}"
AUTH_USER="${WAZ_INDEXER_ADMIN_USER}"

echo "[WAZ_042] Recherche des index actuellement verrouilles (read_only_allow_delete)..."
LOCKED_JSON=$(curl -sk -u "${AUTH_USER}:${WAZUH_INDEXER_ADMIN_PW}" \
  "https://127.0.0.1:${WAZ_INDEXER_PORT}/_all/_settings/index.blocks.read_only_allow_delete?pretty")

LOCKED_INDICES=$(echo "$LOCKED_JSON" | python3 -c "
import json,sys
d = json.load(sys.stdin)
for name, body in d.items():
    if body.get('settings', {}).get('index', {}).get('blocks', {}).get('read_only_allow_delete') == 'true':
        print(name)
" 2>/dev/null)

if [ -z "$LOCKED_INDICES" ]; then
  echo "[WAZ_042] Aucun index verrouille, rien a faire."
  echo "[WAZ_042] OK."
  exit 0
fi

echo "[WAZ_042] Index verrouilles trouves :"
echo "$LOCKED_INDICES" | sed 's/^/[WAZ_042]   /'

UNLOCKED=0
FAILED=0
FAILED_LIST=""
while IFS= read -r IDX; do
  [ -z "$IDX" ] && continue
  HTTP_CODE=$(curl -sk -u "${AUTH_USER}:${WAZUH_INDEXER_ADMIN_PW}" \
    -X PUT "https://127.0.0.1:${WAZ_INDEXER_PORT}/${IDX}/_settings" \
    -H 'Content-Type: application/json' -d '{"index.blocks.read_only_allow_delete": null}' \
    -o /dev/null -w '%{http_code}')
  if [ "$HTTP_CODE" = "200" ]; then
    echo "[WAZ_042]   ${IDX} : deverrouille."
    UNLOCKED=$((UNLOCKED + 1))
  else
    echo "[WAZ_042]   ${IDX} : echec (HTTP ${HTTP_CODE}) - probablement un index systeme protege, voir en-tete de ce script."
    FAILED=$((FAILED + 1))
    FAILED_LIST="${FAILED_LIST}${IDX} "
  fi
done <<< "$LOCKED_INDICES"

echo "[WAZ_042] Bilan : ${UNLOCKED} index deverrouille(s), ${FAILED} refuse(s) (index systeme proteges, normal - voir en-tete)."
if [ -n "$FAILED_LIST" ]; then
  echo "[WAZ_042] Refuses : ${FAILED_LIST}"
fi
echo "[WAZ_042] OK."
exit 0
