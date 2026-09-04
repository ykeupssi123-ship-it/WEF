#!/bin/bash
# WAZ_043_DASHBOARD_FIELDS_REFRESH - WEF_WAZ_RUN_FIELDREFRESH - Purge le
# cache de champs perime du Wazuh Dashboard
#
# AJOUTE LE 2026-08-31 (point #9 de la mission - jobs RUN rejouables
# pour chaque erreur reelle rencontree - demande explicite de
# l'utilisateur). Symptome reel observe cote utilisateur, capture
# d'ecran a l'appui : panneaux MITRE ATT&CK/Overview du Dashboard en
# erreur - "Saved field 'rule.mitre.technique' is invalid for use with
# the 'Terms' aggregation."
#
# DIAGNOSTIC REEL (jamais suppose) : le Wazuh Dashboard (comme tout
# derive d'OpenSearch Dashboards/Kibana) met en cache la LISTE DES
# CHAMPS de chaque "index pattern" au moment de sa creation - stockee
# comme objet dans l'index systeme ".kibana", jamais reinterrogee
# automatiquement contre le mappage REEL de l'indexeur par la suite.
# Si ce cache a ete capture a un moment ou le mappage etait errone
# (ex. avant l'application du bon modele - voir
# WAZ_014C_ALERTS_TEMPLATE.sh -, ou apres un changement de mappage), les
# visualisations pre-construites du Dashboard (qui referencent des noms
# de champs exacts, ex. "rule.mitre.technique" plutot que
# "rule.mitre.technique.keyword") echouent - meme quand le mappage reel
# de l'indexeur est parfaitement correct.
#
# ACTION DE CE JOB : supprime l'objet "index pattern" perime pour que le
# Dashboard le redecouvre a neuf contre le mappage ACTUEL. ETAPE
# MANUELLE RESTANTE, IMPOSSIBLE A AUTOMATISER COTE SERVEUR (le
# declenchement de la redecouverte se fait cote NAVIGATEUR, au chargement
# de la page) : rechargez la page du Dashboard une fois ce job termine -
# l'assistant de sante ("health-check") ou la premiere visite recree
# l'index pattern automatiquement avec les bons champs.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

WAZUH_INDEXER_ADMIN_PW="$(read_or_generate_secret "$WAZ_INDEXER_ADMIN_PASSWORD_FILE" non)" || exit 1
WAZ_INDEXER_PORT="${WAZ_INDEXER_PORT:-9200}"
AUTH_USER="${WAZ_INDEXER_ADMIN_USER}"

# Liste volontairement limitee aux index-patterns reellement utilises
# par cette usine (confirme par recherche reelle dans .kibana) - jamais
# une purge aveugle de tous les objets sauvegardes.
INDEX_PATTERNS="wazuh-alerts-* wazuh-states-vulnerabilities-* wazuh-monitoring-* wazuh-statistics-*"

echo "[WAZ_043] Purge des index-patterns perimes (redecouverte a la prochaine visite du Dashboard)..."
PURGED=0
for PATTERN in $INDEX_PATTERNS; do
  DOC_ID="index-pattern:${PATTERN}"
  HTTP_CODE=$(curl -sk -u "${AUTH_USER}:${WAZUH_INDEXER_ADMIN_PW}" \
    -X DELETE "https://127.0.0.1:${WAZ_INDEXER_PORT}/.kibana/_doc/${DOC_ID}" \
    -o /dev/null -w '%{http_code}')
  case "$HTTP_CODE" in
    200)
      echo "[WAZ_043]   ${PATTERN} : purge (etait present)."
      PURGED=$((PURGED + 1))
      ;;
    404)
      echo "[WAZ_043]   ${PATTERN} : deja absent, ignore."
      ;;
    *)
      echo "[WAZ_043]   ${PATTERN} : echec inattendu (HTTP ${HTTP_CODE})."
      ;;
  esac
done

echo "[WAZ_043] ${PURGED} index-pattern(s) purge(s)."
echo "[WAZ_043] --------------------------------------------------------------"
echo "[WAZ_043] ETAPE MANUELLE RESTANTE (cote navigateur, jamais automatisable"
echo "[WAZ_043] depuis ce serveur) : rechargez la page du Wazuh Dashboard - il"
echo "[WAZ_043] recreera automatiquement les index-patterns purges avec les"
echo "[WAZ_043] bons champs des la premiere visite/health-check."
echo "[WAZ_043] --------------------------------------------------------------"
echo "[WAZ_043] OK."
exit 0
