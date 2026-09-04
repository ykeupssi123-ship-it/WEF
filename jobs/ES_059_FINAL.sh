#!/bin/bash
# ES_059_FINAL - WEF_ES_BLD_VAULTSEAL - Scellement DEFINITIF du coffre PKI partage
# Ne se declenche qu'apres LOGSTASH_COLLECTOR_ONLINE (Logstash confirme
# ne plus avoir besoin d'ecrire dans le coffre PKI partage). Voir
# discussion ES_059 vs ES_059_FINAL : verrou local tot, scellement
# global tard, pour ne jamais bloquer un consommateur legitime en cours
# de construction.
set -uo pipefail
source "$VARS_FILE"
if lsattr "${PKI_DIR}"/*.crt 2>/dev/null | grep -q "^----i"; then
  echo "[ES_059_FINAL] Coffre PKI deja scelle, ignore."
  echo "[ES_059_FINAL] OK."
  exit 0
fi
echo "[ES_059_FINAL] Scellement definitif du coffre PKI partage..."
chattr +i "${PKI_DIR}"/*.crt "${PKI_DIR}"/*.pem 2>/dev/null || true
echo "[ES_059_FINAL] OK."
exit 0
