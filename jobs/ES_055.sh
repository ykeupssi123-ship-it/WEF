#!/bin/bash
# ES_055 - WEF_ES_RUN_HARDRSTRTTEST - Redemarrage complet a froid
#
# CORRECTIF 2026-08-14 (audit systemique suite a l'incident ES_052) :
# ce job appelait "systemctl restart elasticsearch" sans meme lire son
# code de sortie, et se declarait OK inconditionnellement. Corrige :
# verification reelle via wait_for_service_active (lib/commun.sh).
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
echo "[ES_055] Redemarrage complet (systemctl restart)..."
systemctl restart elasticsearch 2>/dev/null || true
if wait_for_service_active elasticsearch 120 5; then
  echo "[ES_055] Confirme actif (systemctl is-active)."
  echo "[ES_055] OK."
  exit 0
fi
exit 1
