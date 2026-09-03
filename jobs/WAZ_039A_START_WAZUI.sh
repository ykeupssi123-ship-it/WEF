#!/bin/bash
# WAZ_039A_START_WAZUI - WEF_WAZ_RUN_STARTWAZUI
# Reallumage : redemarre wazuh-indexer PUIS wazuh-dashboard (l'ordre
# compte - le Dashboard depend de l'indexeur pour fonctionner). Premier
# job de la cascade "retour vers Wazuh" a toucher les services - doit
# tourner avant WAZ_039C (la coupure inverse ES -> wazuh-indexer a
# besoin de l'indexeur vivant pour y ecrire).
#
# AJOUTE LE 2026-09-03 (refonte demandee par l'utilisateur, voir
# docs/JOURNAL_TECHNIQUE.md, decoupage du monolithique
# WAZ_039_MODE_SOUVERAIN.sh d'origine).
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

echo "[WAZ_039A_START_WAZUI] Redemarrage de wazuh-indexer..."
systemctl daemon-reload
systemctl enable wazuh-indexer 2>/dev/null || true
if ! systemctl restart wazuh-indexer; then
  echo "[WAZ_039A_START_WAZUI] ERREUR : wazuh-indexer.service n'a pas demarre. Diagnostic :" >&2
  journalctl -u wazuh-indexer -n 30 --no-pager 2>/dev/null || true
  exit 1
fi
if ! wait_for_service_active wazuh-indexer 180 5; then
  echo "[WAZ_039A_START_WAZUI] ERREUR : wazuh-indexer n'a pas pu etre confirme actif." >&2
  exit 1
fi

echo "[WAZ_039A_START_WAZUI] Redemarrage de wazuh-dashboard..."
systemctl enable wazuh-dashboard 2>/dev/null || true
if ! systemctl restart wazuh-dashboard; then
  echo "[WAZ_039A_START_WAZUI] ERREUR : wazuh-dashboard.service n'a pas demarre. Diagnostic :" >&2
  journalctl -u wazuh-dashboard -n 30 --no-pager 2>/dev/null || true
  exit 1
fi
if ! wait_for_service_active wazuh-dashboard 120 5; then
  echo "[WAZ_039A_START_WAZUI] ERREUR : wazuh-dashboard n'a pas pu etre confirme actif." >&2
  exit 1
fi

echo "[WAZ_039A_START_WAZUI] OK."
exit 0
