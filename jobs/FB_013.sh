#!/bin/bash
# FB_013 - WEF_FB_BLD_SVCSTART - Demarrage du capteur
set -uo pipefail
source "$VARS_FILE"
# CORRECTIF 2026-08-19 (meme famille d'incident reel que LS_026_FINAL,
# wef-elk-core) : "systemctl enable --now" ne redemarre pas un service
# deja actif. Enable + restart explicite.
echo "[FB_013] Demarrage de Filebeat..."
systemctl enable filebeat 2>/dev/null || true
if ! systemctl restart filebeat; then
  echo "[FB_013] ERREUR : filebeat.service n'a pas demarre. Diagnostic (journalctl -u filebeat -n 30) :"
  journalctl -u filebeat -n 30 --no-pager 2>/dev/null || true
  exit 1
fi
echo "[FB_013] OK."
exit 0
