#!/bin/bash
# WAZ_014 - WEF_WAZ_BLD_STARTINDXR - Demarrage du moteur de stockage
set -uo pipefail
source "$VARS_FILE"
# CORRECTIF 2026-08-19 (meme famille d'incident reel que LS_026_FINAL,
# wef-elk-core) : "systemctl enable --now" ne redemarre pas un service
# deja actif. Enable + restart explicite.
echo "[WAZ_014] Demarrage de wazuh-indexer..."
systemctl daemon-reload
systemctl enable wazuh-indexer 2>/dev/null || true
if ! systemctl restart wazuh-indexer; then
  echo "[WAZ_014] ERREUR : wazuh-indexer.service n'a pas demarre. Diagnostic (journalctl -u wazuh-indexer -n 30) :"
  journalctl -u wazuh-indexer -n 30 --no-pager 2>/dev/null || true
  exit 1
fi
echo "[WAZ_014] OK."
exit 0
