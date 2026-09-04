#!/bin/bash
# MB_013 - WEF_MB_BLD_SVCSTART - Demarrage du capteur souverain
set -uo pipefail
source "$VARS_FILE"
# CORRECTIF 2026-08-19 (meme famille d'incident reel que LS_026_FINAL,
# wef-elk-core) : "systemctl enable --now" ne redemarre pas un service
# deja actif. Enable + restart explicite.
echo "[MB_013] Demarrage de Metricbeat..."
systemctl enable metricbeat 2>/dev/null || true
if ! systemctl restart metricbeat; then
  echo "[MB_013] ERREUR : metricbeat.service n'a pas demarre. Diagnostic (journalctl -u metricbeat -n 30) :"
  journalctl -u metricbeat -n 30 --no-pager 2>/dev/null || true
  exit 1
fi
echo "[MB_013] OK."
exit 0
