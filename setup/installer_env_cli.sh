#!/bin/bash
# installer_env_cli.sh - AJOUTE LE 2026-09-09 (demande explicite
# utilisateur : pouvoir taper, depuis n'importe quel repertoire d'une
# session CLI Linux, "$APP_BIN/order.sh <job> <raison>" et obtenir le
# resultat voulu, peu importe ou le depot a ete clone).
#
# PROBLEME REEL : vars.conf definit deja APP_HOME/APP_BIN/APP_INF (voir
# son en-tete), mais vars.conf n'est source QUE par les scripts du
# projet eux-memes (orchestrator.sh, jobs/*.sh, bin/*.sh) - jamais par
# un shell de connexion SSH ordinaire. Sans ce script, ces variables
# restent invisibles a l'invite de commande elle-meme.
#
# CORRECTIF : ce script ecrit un fichier dans /etc/profile.d/, charge
# automatiquement par bash a CHAQUE connexion (interactive login shell)
# de CHAQUE utilisateur sur la machine - meme principe que
# svc_orch.sh pour l'orchestrateur lui-meme,
# applique ici a l'environnement CLI.
#
# A LANCER UNE SEULE FOIS (racine, root) - idempotent, peut et DOIT etre
# relance sans risque si le depot est deplace ou clone sur une nouvelle
# machine (ecrase simplement l'ancien chemin par le nouveau).
#
# Usage apres installation (nouvelle session, ou "source /etc/profile") :
#   $APP_BIN/order.sh <JOB_ID> "<raison>"
#   $APP_BIN/hold.sh <JOB_ID> "<raison>"
#   $APP_BIN/monitor.sh
set -uo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "ERREUR : ce script doit etre lance en root (ecriture dans /etc/profile.d/)." >&2
  exit 1
fi

# CE SCRIPT vit dans setup/, jamais a la racine - meme calcul que
# svc_orch.sh pour retrouver la racine reelle du
# projet (ou vivent orchestrator.sh, vars.conf, jobs_table.csv).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_FILE="/etc/profile.d/wef-app-env.sh"

if [ ! -f "${SCRIPT_DIR}/vars.conf" ]; then
  echo "ERREUR : ${SCRIPT_DIR}/vars.conf introuvable - SCRIPT_DIR ne semble pas pointer vers la racine du projet." >&2
  exit 1
fi

echo "[installer_env_cli] Ecriture de ${PROFILE_FILE} pour APP_HOME=${SCRIPT_DIR}..."
cat > "$PROFILE_FILE" << ENVEOF
# Genere par setup/installer_env_cli.sh - NE PAS EDITER A LA MAIN
# (relancez ce script si le depot WAZ_ELK_FACTORY est deplace/re-clone).
export APP_HOME="${SCRIPT_DIR}"
export APP_BIN="${SCRIPT_DIR}/bin"
export APP_INF="${SCRIPT_DIR}/setup"
ENVEOF
chmod 644 "$PROFILE_FILE"

echo "[installer_env_cli] OK. Variables actives pour toute NOUVELLE session (SSH, su -, etc)."
echo "Pour les rendre actives immediatement dans CETTE session :"
echo "  source ${PROFILE_FILE}"
echo "Verification :"
echo "  echo \$APP_BIN   # doit afficher : ${SCRIPT_DIR}/bin"
echo "  \$APP_BIN/order.sh <JOB_ID> \"<raison>\""
echo "  \$APP_INF/MNT_diagnostic.sh   # ex. : n'importe quel script d'admin (setup/), meme principe"
exit 0
