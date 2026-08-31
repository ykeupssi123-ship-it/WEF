#!/bin/bash
# installer_service_tableau_de_bord.sh - AJOUTE LE 2026-08-20
#
# Installe tableau_de_bord.py (toile de dependances live, esprit BMC
# Control-M - voir l'en-tete de ce fichier pour le detail complet) comme
# service systemd permanent, et ouvre son port dans firewalld.
#
# A LANCER UNE SEULE FOIS (racine, root) - idempotent, peut etre relance
# sans risque (ex: si DASHBOARD_PORT change dans vars.conf plus tard).
#
# A la difference de wef-orchestrateur.service (Type=oneshot, declenche
# a la demande par l'operateur), ce service est concu pour rester
# TOUJOURS actif en arriere-plan (Type=simple, enable --now des
# l'installation) : c'est un ecran de suivi permanent, pas une tache
# ponctuelle.
#
# Usage apres installation :
#   Ouvrir un navigateur sur http://<IP_DU_SERVEUR>:<DASHBOARD_PORT>/
#   (DASHBOARD_PORT dans vars.conf, 8088 par defaut) - la page se
#   rafraichit toute seule (5s), toujours a jour, lecture seule stricte.
set -uo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "ERREUR : ce script doit etre lance en root (installation d'un service systemd + regle firewalld)." >&2
  exit 1
fi

if ! command -v systemctl &>/dev/null; then
  echo "ERREUR : systemctl introuvable - cette machine ne semble pas utiliser systemd. Installation impossible." >&2
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  echo "ERREUR : python3 introuvable (attendu present via dnf). Installation impossible." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export VARS_FILE="$SCRIPT_DIR/vars.conf"
source "$VARS_FILE"
DASHBOARD_PORT="${DASHBOARD_PORT:-8088}"
UNIT_PATH="/etc/systemd/system/wef-tableau-de-bord.service"

echo "[installer_service_tableau_de_bord] Installation du service pour : ${SCRIPT_DIR}/tableau_de_bord.py (port ${DASHBOARD_PORT})"

if [ ! -f "${SCRIPT_DIR}/tableau_de_bord.py" ]; then
  echo "ERREUR : ${SCRIPT_DIR}/tableau_de_bord.py introuvable." >&2
  exit 1
fi

# Meme zone que Kibana (UI_Zone, creee par KB_006) - ce tableau de bord
# est, comme Kibana, une interface consultee par un operateur humain
# depuis son navigateur. Recreation idempotente au cas ou ce script
# serait lance avant le reste de la chaine (defensif, meme discipline
# que KB_006).
if command -v firewall-cmd &>/dev/null; then
  if ! firewall-cmd --get-zones 2>/dev/null | grep -qw UI_Zone; then
    echo "[installer_service_tableau_de_bord] Zone UI_Zone absente, creation..."
    firewall-cmd --permanent --new-zone=UI_Zone || true
  fi
  echo "[installer_service_tableau_de_bord] Ouverture du port ${DASHBOARD_PORT}/tcp sur UI_Zone..."
  firewall-cmd --permanent --zone=UI_Zone --add-port="${DASHBOARD_PORT}/tcp"
  firewall-cmd --reload
else
  echo "[installer_service_tableau_de_bord] AVERTISSEMENT : firewall-cmd introuvable, port ${DASHBOARD_PORT} non garanti accessible depuis l'exterieur." >&2
fi

cat > "$UNIT_PATH" << UNITEOF
[Unit]
Description=WAZ_ELK_FACTORY - Tableau de bord visuel (toile de dependances, lecture seule)
After=multi-user.target

[Service]
Type=simple
WorkingDirectory=${SCRIPT_DIR}
ExecStart=/usr/bin/python3 ${SCRIPT_DIR}/tableau_de_bord.py
Restart=on-failure
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
UNITEOF

echo "[installer_service_tableau_de_bord] Unite ecrite dans ${UNIT_PATH}."
systemctl daemon-reload
systemctl enable --now wef-tableau-de-bord

# Verification explicite (jamais supposer qu'un service demarre juste
# parce qu'on l'a demande - meme discipline que ES_011/KB_024).
sleep 2
if systemctl is-active --quiet wef-tableau-de-bord; then
  echo "[installer_service_tableau_de_bord] Service actif (systemctl is-active confirme)."
else
  echo "[installer_service_tableau_de_bord] ERREUR : le service ne semble pas actif. Voir : journalctl -u wef-tableau-de-bord -n 40" >&2
  exit 1
fi

if command -v curl &>/dev/null; then
  if curl -s -o /dev/null -w "" --max-time 5 "http://127.0.0.1:${DASHBOARD_PORT}/"; then
    echo "[installer_service_tableau_de_bord] Reponse HTTP confirmee sur 127.0.0.1:${DASHBOARD_PORT}."
  else
    echo "[installer_service_tableau_de_bord] AVERTISSEMENT : pas de reponse HTTP locale sur le port ${DASHBOARD_PORT} - voir journalctl -u wef-tableau-de-bord." >&2
  fi
fi

echo "[installer_service_tableau_de_bord] OK."
echo ""
echo "Ouvrir dans un navigateur : http://<IP_DU_SERVEUR>:${DASHBOARD_PORT}/"
echo "Consulter les logs        : journalctl -u wef-tableau-de-bord -f"
exit 0
