#!/bin/bash
# WAZ_015 - WEF_WAZ_BLD_STARTMNGR - Demarrage du cerveau d'analyse
set -uo pipefail
source "$VARS_FILE"
# CORRECTIF 2026-08-19 (meme famille d'incident reel que LS_026_FINAL,
# wef-elk-core) : "systemctl enable --now" ne redemarre pas un service
# deja actif. Enable + restart explicite.
#
# CORRECTIF 2026-08-30 (incident reel wef-elk-core, reproduit en reel
# lors d'un redemarrage de la VM) : le paquet Wazuh fixe
# TimeoutStartSec=45s pour wazuh-manager.service (valeur vendor,
# /usr/lib/systemd/system/wazuh-manager.service - jamais modifiee
# directement, un paquet peut l'ecraser a la prochaine mise a jour).
# Insuffisant quand wazuh-indexer/wazuh-manager/wazuh-dashboard
# demarrent tous les trois en meme temps au boot (charge CPU/E-S
# partagee) : "systemctl restart" rend alors un code d'echec par
# timeout, alors qu'un simple nouvel essai quelques secondes plus tard
# reussit sans autre changement (confirme en reel : echec puis succes
# immediat sur reessai manuel, meme machine, memes services). Fixe par
# un drop-in systemd (survit aux mises a jour du paquet, contrairement
# a editer le .service fourni directement) - jamais suppose applique
# sans verification (daemon-reload explicite + wait_for_service_active
# reel ensuite, pas seulement le code de sortie de systemctl restart).
mkdir -p /etc/systemd/system/wazuh-manager.service.d
cat > /etc/systemd/system/wazuh-manager.service.d/override.conf << 'EOF'
[Service]
TimeoutStartSec=180
EOF
systemctl daemon-reload

echo "[WAZ_015] Demarrage de wazuh-manager..."
systemctl enable wazuh-manager 2>/dev/null || true
systemctl restart wazuh-manager 2>/dev/null || true

PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
if ! wait_for_service_active wazuh-manager 180 5; then
  echo "[WAZ_015] ERREUR : wazuh-manager.service n'a pas demarre. Diagnostic (journalctl -u wazuh-manager -n 30) :"
  journalctl -u wazuh-manager -n 30 --no-pager 2>/dev/null || true
  exit 1
fi
sleep 5
echo "[WAZ_015] OK."
exit 0
