#!/bin/bash
# WAZ_039_WAZUH_TRIGGER - WEF_WAZ_RUN_TRGWAZUH
# Vanne de declenchement : point d'entree unique de la bascule complete
# de retour vers Wazuh Dashboard/wazuh-indexer. Miroir exact de
# WAZ_035_KIBANA_TRIGGER (voir son en-tete) - aucune action reelle sur
# les services ou les donnees, ouvre seulement la cascade
# (WAZ_039A -> WAZ_039B -> WAZ_039C -> WAZ_039D -> WAZ_040) en effacant
# les marqueurs d'etat de chacune de ses etapes.
#
# AJOUTE LE 2026-09-03 (refonte demandee par l'utilisateur, voir
# docs/JOURNAL_TECHNIQUE.md). REMPLACE l'ancien WAZ_039_MODE_SOUVERAIN.sh
# monolithique (conserve dans l'historique git).
#
# UTILISATION MANUELLE :
#   ./forcer_job.sh WAZ_039_WAZUH_TRIGGER "raison" && ./orchestrator.sh
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

ROUTE_STATE_FILE="${STATE_DIR}/WAZ_ALERTS_ROUTE.state"
CURRENT_ROUTE="$(cat "$ROUTE_STATE_FILE" 2>/dev/null || echo INDEXER)"
if [ "$CURRENT_ROUTE" != "ELASTICSEARCH" ]; then
  echo "[WAZ_039_WAZUH_TRIGGER] Deja en mode Wazuh/Souverain (route=${CURRENT_ROUTE} dans ${ROUTE_STATE_FILE}), rien a declencher."
  exit 0
fi

echo "[WAZ_039_WAZUH_TRIGGER] Declenchement du retour vers Wazuh - effacement des marqueurs de la cascade..."
for cond in WAZ_WAZUI_STARTED WAZ_PIPELINE_INDEXER_ACTIVE WAZ_ES_DATA_CUT WAZ_PIPELINE_SOUVERAIN_ACTIVE WAZ_KIBANA_MUTED; do
  rm -f "${STATE_DIR}/${cond}.ok"
done

echo "[WAZ_039_WAZUH_TRIGGER] OK. Cascade ouverte - lancez ./orchestrator.sh pour l'executer (chaque etape reste individuellement gelable via SKIP_JOBS)."
exit 0
