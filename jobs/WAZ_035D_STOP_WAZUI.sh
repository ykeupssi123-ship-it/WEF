#!/bin/bash
# WAZ_035D_STOP_WAZUI - WEF_WAZ_RUN_STOPWAZUI
# Extinction : arrete wazuh-dashboard ET wazuh-indexer (mode Kibana
# EXCLUSIF, demande explicite utilisateur 2026-09-03 - voir
# docs/JOURNAL_TECHNIQUE.md). Dernier job de la cascade "vers Kibana" a
# toucher les services/donnees - ecrit le marqueur officiel de bascule
# (WAZ_ALERTS_ROUTE.state) ici, une fois que TOUT ce qui precede
# (jobs dependants en pause, historique coupe, pipeline reaiguille) est
# confirme fait.
#
# AJOUTE LE 2026-09-03. DOIT tourner APRES WAZ_035B (coupure de
# l'historique, qui a besoin de wazuh-indexer encore vivant pour le
# lire) et WAZ_035C (pipeline deja repointe vers Elasticsearch, sinon
# arreter l'indexeur AVANT la reecriture du pipeline laisserait une
# fenetre ou Logstash tente d'ecrire vers un wazuh-indexer deja mort).
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

ROUTE_STATE_FILE="${STATE_DIR}/WAZ_ALERTS_ROUTE.state"

echo "[WAZ_035D_STOP_WAZUI] Extinction de wazuh-dashboard..."
systemctl stop wazuh-dashboard 2>/dev/null || true
systemctl disable wazuh-dashboard 2>/dev/null || true

echo "[WAZ_035D_STOP_WAZUI] Extinction de wazuh-indexer..."
systemctl stop wazuh-indexer 2>/dev/null || true
systemctl disable wazuh-indexer 2>/dev/null || true

if systemctl is-active --quiet wazuh-dashboard || systemctl is-active --quiet wazuh-indexer; then
  echo "[WAZ_035D_STOP_WAZUI] ERREUR : wazuh-dashboard et/ou wazuh-indexer toujours actif(s) apres 'systemctl stop'." >&2
  systemctl status wazuh-dashboard wazuh-indexer --no-pager 2>/dev/null || true
  exit 1
fi

echo "ELASTICSEARCH" > "$ROUTE_STATE_FILE"
echo "[WAZ_035D_STOP_WAZUI] Bascule confirmee : wazuh-dashboard et wazuh-indexer arretes, alertes Wazuh -> Elasticsearch/Kibana exclusivement."
echo "[WAZ_035D_STOP_WAZUI] OK."
exit 0
