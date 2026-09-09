#!/bin/bash
# WAZ_020_VERIFY - WEF_WAZ_RUN_INDEXVERIFY - Verification de la bonne inscription
#
# CORRIGE LE 2026-08-30 suite au diagnostic reel de l'echec du 2026-08-19
# (voir en-tetes WAZ_013C_INDXR_ADMINCERT.sh / WAZ_014A_INDXR_ADMINPW.sh
# pour le detail complet) :
#   - WAZ_INDEXER_ADMIN_PASSWORD vient desormais de
#     WAZ_INDEXER_ADMIN_PASSWORD_FILE (jamais vars.conf en clair) - lu
#     ici en LECTURE SEULE (generer=non) : ce job ne doit JAMAIS creer ce
#     secret lui-meme, seulement le job qui le pousse reellement au
#     cluster (WAZ_014A, plus tot dans la chaine) en a la responsabilite.
#     Si le fichier est absent ici, c'est WAZ_014A qui n'a pas tourne
#     avant - erreur claire plutot qu'un mot de passe invente a la place.
#   - Ancienne verification trop faible : `grep -q '"count"'` passe MEME
#     quand le compte reel est 0 (reponse valide `{"count":0,...}` d'un
#     index existant mais vide) - ne prouve donc jamais qu'une alerte a
#     reellement ete indexee, seulement que l'appel HTTP a repondu.
#   - Nouvelle boucle de nouvelle tentative (6 x 5s = 30s max) : le
#     pipeline agent -> manager -> indexer a un delai d'ingestion reel
#     (jamais instantane), un compte encore a 0 juste apres WAZ_019_FLOOD
#     n'est pas forcement une erreur definitive - ne pas confondre "pas
#     encore" avec "jamais" (meme discipline que wait_for_service_active,
#     lib/commun.sh).
#   - ES_PORT designe Elasticsearch (vars.conf), pas wazuh-indexer -
#     incident reel de collision de port avec Elasticsearch (les deux
#     tournent en permanence sur cette VM), voir WAZ_013D_INDXR_PORTS.sh
#     pour le detail complet. Utilise desormais WAZ_INDEXER_PORT.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

WAZ_INDEXER_ADMIN_PASSWORD="$(read_or_generate_secret "$WAZ_INDEXER_ADMIN_PASSWORD_FILE" non)" || exit 1
WAZ_INDEXER_PORT="${WAZ_INDEXER_PORT:-9201}"

# BUDGET REMONTE LE 2026-09-09 (incident reel, deploiement MIPREL2,
# meme VM que l'incident CPU/WAZ_014 documente le meme jour) : 6
# tentatives x 5s = 30s total etait beaucoup trop court une fois la
# realite de cette VM etablie (2 vCPU, 6 services JVM/Node simultanes -
# ES/Logstash/Kibana/wazuh-indexer/wazuh-manager/wazuh-dashboard).
# Preuve reelle du vrai goulot d'etranglement : "systemctl status
# logstash" montrait "logstash.outputs.http ... Connect to
# 127.0.0.1:9200 ... Connexion refusee" - le pipeline WAZ_014B est
# correctement configure (port verifie, cible le bon port reel de
# wazuh-indexer), mais l'indexeur devient transitoirement injoignable
# sous cette charge. `retry_non_idempotent => true` (WAZ_014B) et la
# Persistent Queue Logstash finissent par livrer les documents en
# attente une fois l'indexeur stable - il faut juste largement plus de
# temps que 30s pour l'observer. Jamais rejoue WAZ_019_FLOOD pour ce
# meme incident : le manager avait deja reellement genere les alertes
# (confirme : 3862 occurrences de la regle 100102 dans
# /var/ossec/logs/alerts/alerts.log) - seul l'acheminement avait besoin
# de plus de temps, pas une nouvelle injection.
WAZ_INDEX_VERIFY_TIMEOUT_SEC="${WAZ_INDEX_VERIFY_TIMEOUT_SEC:-240}"
INTERVALLE=10
TENTATIVES=$(( (WAZ_INDEX_VERIFY_TIMEOUT_SEC + INTERVALLE - 1) / INTERVALLE ))

echo "[WAZ_020_VERIFY] Verification de l'indexation des alertes (jusqu'a ${WAZ_INDEX_VERIFY_TIMEOUT_SEC}s)..."
i=1
while [ "$i" -le "$TENTATIVES" ]; do
  curl -sk -u "${WAZ_INDEXER_ADMIN_USER}:${WAZ_INDEXER_ADMIN_PASSWORD}" \
    "https://127.0.0.1:${WAZ_INDEXER_PORT}/wazuh-alerts-*/_count" -o "${WORK_TMP_DIR}/waz020.json"
  COUNT=$(python3 -c "import json,sys
try:
    d = json.load(open('${WORK_TMP_DIR}/waz020.json'))
    print(int(d.get('count', 0)))
except Exception:
    print(-1)" 2>/dev/null)
  if [ "${COUNT:-0}" -gt 0 ] 2>/dev/null; then
    echo "[WAZ_020_VERIFY] OK (${COUNT} alertes indexees, tentative ${i}/${TENTATIVES})."
    rm -f "${WORK_TMP_DIR}/waz020.json"
    exit 0
  fi
  echo "[WAZ_020_VERIFY] Pas encore d'alerte indexee (tentative ${i}/${TENTATIVES}, reponse : $(cat "${WORK_TMP_DIR}/waz020.json" 2>/dev/null | head -c 200))..."
  i=$((i + 1))
  [ "$i" -le "$TENTATIVES" ] && sleep "$INTERVALLE"
done

echo "[WAZ_020_VERIFY] ERREUR : toujours 0 alerte indexee apres ${WAZ_INDEX_VERIFY_TIMEOUT_SEC}s. Diagnostic :" >&2
echo "[WAZ_020_VERIFY] --- Derniere reponse de l'indexeur (${WORK_TMP_DIR}/waz020.json) ---" >&2
cat "${WORK_TMP_DIR}/waz020.json" 2>/dev/null >&2
echo "[WAZ_020_VERIFY] --- Alertes reellement generees par le manager (regle 100102, test de charge) ---" >&2
grep -c '"rule":{"id":"100102"' /var/ossec/logs/alerts/alerts.json 2>/dev/null >&2 || echo "(introuvable ou aucune)" >&2
echo "[WAZ_020_VERIFY] --- Dernieres erreurs Logstash (pipeline wazuh-alerts, voir WAZ_014B) ---" >&2
grep -i "wazuh-alerts" /var/log/logstash/logstash-plain.log 2>/dev/null | tail -n 15 >&2
echo "[WAZ_020_VERIFY] --- Etat de wazuh-indexer ---" >&2
systemctl status wazuh-indexer --no-pager 2>/dev/null | head -8 >&2
exit 1
