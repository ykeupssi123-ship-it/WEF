#!/bin/bash
# KB_018 - WEF_KB_BLD_SVCSTART - Demarrage de l'interface isolee
set -uo pipefail
source "$VARS_FILE"
# CORRECTIF 2026-08-19 (meme famille d'incident reel que LS_026_FINAL,
# wef-elk-core) : "systemctl enable --now" ne redemarre pas un service
# deja actif - un config regeneree par les jobs precedents pourrait
# donc ne jamais etre chargee si Kibana tournait deja depuis un essai
# anterieur. Enable + restart explicite, comme LS_026_FINAL.
echo "[KB_018] Demarrage de Kibana..."
systemctl enable kibana 2>/dev/null || true
if ! systemctl restart kibana; then
  echo "[KB_018] ERREUR : kibana.service n'a pas demarre. Diagnostic (journalctl -u kibana -n 30) :"
  journalctl -u kibana -n 30 --no-pager 2>/dev/null || true
  echo "[KB_018] Voir aussi /var/log/kibana/*.log pour le detail complet."
  exit 1
fi
echo "[KB_018] OK."
exit 0
