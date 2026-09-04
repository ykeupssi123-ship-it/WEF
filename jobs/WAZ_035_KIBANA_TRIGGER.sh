#!/bin/bash
# WAZ_035_KIBANA_TRIGGER - WEF_WAZ_RUN_TRGKIBANA
# Vanne de declenchement : point d'entree unique de la bascule complete
# vers Kibana. Ne fait AUCUNE action reelle sur les services ou les
# donnees - son seul role est de demarrer la cascade granulaire
# (WAZ_035A -> WAZ_035B -> WAZ_035C -> WAZ_035D -> WAZ_036 -> WAZ_037 ->
# WAZ_038), en effacant les marqueurs d'etat de chacune de ses etapes
# pour qu'un "./orchestrator.sh" normal, juste apres, les rejoue dans
# l'ordre.
#
# AJOUTE LE 2026-09-03 (refonte demandee par l'utilisateur, voir
# docs/JOURNAL_TECHNIQUE.md) : REMPLACE l'ancien WAZ_035_MODE_CONVERGENT.sh
# monolithique (conserve dans l'historique git) par une chaine de jobs
# INDEPENDANTS, chacun individuellement gelable via SKIP_JOBS (vars.conf)
# - c'etait impossible avec un seul gros script. Chaque etape de la
# cascade est documentee dans son propre fichier.
#
# UTILISATION MANUELLE (bascule en cours d'exploitation, pas au premier
# deploiement) :
#   ./bin/order_job.sh WAZ_035_KIBANA_TRIGGER "raison" && ./orchestrator.sh
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

ROUTE_STATE_FILE="${STATE_DIR}/WAZ_ALERTS_ROUTE.state"
CURRENT_ROUTE="$(cat "$ROUTE_STATE_FILE" 2>/dev/null || echo INDEXER)"
if [ "$CURRENT_ROUTE" = "ELASTICSEARCH" ]; then
  echo "[WAZ_035_KIBANA_TRIGGER] Deja en mode Kibana (route=ELASTICSEARCH dans ${ROUTE_STATE_FILE}), rien a declencher."
  exit 0
fi

# Efface les marqueurs de TOUTE la cascade "vers Kibana" (jamais ceux du
# sens inverse) pour forcer leur reexecution au prochain passage de
# l'orchestrateur - CHAQUE etape verifie quand meme elle-meme l'etat
# reel avant d'agir (idempotence), ce nettoyage sert seulement a rouvrir
# la porte que l'orchestrateur avait refermee (OUT_COND deja .ok) lors
# du premier deploiement a froid.
echo "[WAZ_035_KIBANA_TRIGGER] Declenchement de la bascule vers Kibana - effacement des marqueurs de la cascade..."
for cond in WAZ_DEP_JOBS_PAUSED WAZ_INDEXER_DATA_CUT WAZ_PIPELINE_ELK_ACTIVE WAZ_WAZUI_STOPPED WAZ_INDEX_KIBANA_OK WAZ_CONVERGENT_FLOW_OK WAZ_KIBANA_LOUD; do
  rm -f "${STATE_DIR}/${cond}.ok"
done

echo "[WAZ_035_KIBANA_TRIGGER] OK. Cascade ouverte - lancez ./orchestrator.sh pour l'executer (chaque etape reste individuellement gelable via SKIP_JOBS)."
exit 0
