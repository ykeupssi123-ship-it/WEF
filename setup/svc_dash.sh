#!/bin/bash
# svc_dash.sh (RENOMME LE 2026-09-09, ex-installer_service_tableau_de_bord.sh - nom trop long) - AJOUTE LE 2026-08-20
#
# Installe dashboard.py (toile de dependances live, esprit BMC
# Control-M - voir l'en-tete de ce fichier pour le detail complet) comme
# service systemd permanent, et ouvre son port dans firewalld.
#
# A LANCER UNE SEULE FOIS (racine, root) - idempotent, peut etre relance
# sans risque (ex: si DASHBOARD_PORT change dans vars.conf plus tard).
#
# A la difference de wef.service (Type=oneshot, declenche
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

# CORRIGE LE 2026-09-04 (reorganisation racine/bin/setup) : ce script
# vit desormais dans setup/, jamais a la racine - SCRIPT_DIR doit
# remonter d'un niveau pour continuer a designer la racine reelle
# (vars.conf y reste), BIN_DIR pointe separement vers bin/ (nouvel
# emplacement de dashboard.py).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$SCRIPT_DIR/bin"
export VARS_FILE="$SCRIPT_DIR/vars.conf"
source "$VARS_FILE"
DASHBOARD_PORT="${DASHBOARD_PORT:-8088}"
UNIT_PATH="/etc/systemd/system/wef-dash.service"

echo "[svc_dash] Installation du service pour : ${BIN_DIR}/dashboard.py (port ${DASHBOARD_PORT})"

if [ ! -f "${BIN_DIR}/dashboard.py" ]; then
  echo "ERREUR : ${BIN_DIR}/dashboard.py introuvable." >&2
  exit 1
fi

# Meme zone que Kibana (UI_Zone, creee par KB_006) - ce tableau de bord
# est, comme Kibana, une interface consultee par un operateur humain
# depuis son navigateur. Recreation idempotente au cas ou ce script
# serait lance avant le reste de la chaine (defensif, meme discipline
# que KB_006).
if command -v firewall-cmd &>/dev/null; then
  if ! firewall-cmd --get-zones 2>/dev/null | grep -qw UI_Zone; then
    echo "[svc_dash] Zone UI_Zone absente, creation..."
    firewall-cmd --permanent --new-zone=UI_Zone || true
  fi
  echo "[svc_dash] Ouverture du port ${DASHBOARD_PORT}/tcp sur UI_Zone..."
  firewall-cmd --permanent --zone=UI_Zone --add-port="${DASHBOARD_PORT}/tcp"
  firewall-cmd --reload
else
  echo "[svc_dash] AVERTISSEMENT : firewall-cmd introuvable, port ${DASHBOARD_PORT} non garanti accessible depuis l'exterieur." >&2
fi

cat > "$UNIT_PATH" << UNITEOF
[Unit]
Description=WAZ_ELK_FACTORY - Tableau de bord visuel (toile de dependances, lecture seule)
After=multi-user.target

[Service]
Type=simple
WorkingDirectory=${SCRIPT_DIR}
ExecStart=/usr/bin/python3 ${BIN_DIR}/dashboard.py
Restart=on-failure
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
UNITEOF

echo "[svc_dash] Unite ecrite dans ${UNIT_PATH}."
systemctl daemon-reload
systemctl enable --now wef-dash

# Verification explicite (jamais supposer qu'un service demarre juste
# parce qu'on l'a demande - meme discipline que ES_011/KB_024).
sleep 2
if systemctl is-active --quiet wef-dash; then
  echo "[svc_dash] Service actif (systemctl is-active confirme)."
else
  echo "[svc_dash] ERREUR : le service ne semble pas actif. Voir : journalctl -u wef-dash -n 40" >&2
  exit 1
fi

if command -v curl &>/dev/null; then
  if curl -s -o /dev/null -w "" --max-time 5 "http://127.0.0.1:${DASHBOARD_PORT}/"; then
    echo "[svc_dash] Reponse HTTP confirmee sur 127.0.0.1:${DASHBOARD_PORT}."
  else
    echo "[svc_dash] AVERTISSEMENT : pas de reponse HTTP locale sur le port ${DASHBOARD_PORT} - voir journalctl -u wef-dash." >&2
  fi
fi

echo "[svc_dash] OK."
echo ""
echo "Ouvrir dans un navigateur : http://<IP_DU_SERVEUR>:${DASHBOARD_PORT}/"
echo "Consulter les logs        : journalctl -u wef-dash -f"
exit 0
