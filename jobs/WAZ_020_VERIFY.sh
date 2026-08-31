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

echo "[WAZ_020_VERIFY] Verification de l'indexation des alertes..."
TENTATIVES=6
INTERVALLE=5
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

echo "[WAZ_020_VERIFY] ERREUR, voir ${WORK_TMP_DIR}/waz020.json"; exit 1
