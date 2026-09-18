#!/bin/bash
# INFRA_010_SCHEDULER_INSTALL - WEF_INFRA_RUN_SCHEDINSTALL
#
# AJOUTE LE 2026-09-18 (systeme de calendrier natif, demande explicite :
# "l'orchestrateur doit integrer un systeme de calendrier... ce ne sera
# plus le job qui appelle l'orchestrateur mais c'est l'orchestrateur qui
# sait selon les politiques comment jouer les jobs"). Installe le SEUL
# timer systemd qui declenche bin/scheduler.sh toutes les 60s - point
# d'entree central desormais, remplace le motif precedent (chaque job
# installait SON PROPRE timer independant, voir jobs/WAZ_053_VT_WATCH_GUARDIAN.sh).
#
# Meme motif deja etabli et prouve par setup/svc_orch.sh (voir son
# en-tete) : l'unite systemd est generee par heredoc et pointe directement
# sur le SCRIPT REEL DU DEPOT (${SCRIPT_DIR}/bin/scheduler.sh) - jamais
# une copie figee ailleurs. Consequence voulue : un futur `git pull`
# (deja automatique, voir bin/sync_branch.sh) qui corrige bin/scheduler.sh
# prend effet au TICK SUIVANT, sans jamais rejouer ce job d'installation -
# seule l'unite elle-meme (rarement modifiee) demanderait un rejeu.
#
# ROLE=ALL (voir jobs_table.csv) : necessaire sur ELK_HOST ET AGENT_HOST,
# puisque des jobs planifies peuvent exister sur l'un ou l'autre (voir
# schedules.csv).
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

if [ "$(id -u)" -ne 0 ]; then
  echo "[INFRA_010_SCHEDULER_INSTALL] ERREUR : doit tourner en root (installation d'un service systemd)." >&2
  exit 1
fi
command -v systemctl &>/dev/null || { echo "[INFRA_010_SCHEDULER_INSTALL] ERREUR : systemctl introuvable." >&2; exit 1; }
[ -x "${PROJECT_ROOT}/bin/scheduler.sh" ] || { echo "[INFRA_010_SCHEDULER_INSTALL] ERREUR : ${PROJECT_ROOT}/bin/scheduler.sh introuvable ou non executable." >&2; exit 1; }

SERVICE_PATH="/etc/systemd/system/wef-scheduler.service"
TIMER_PATH="/etc/systemd/system/wef-scheduler.timer"

echo "[INFRA_010_SCHEDULER_INSTALL] Installation du service pour : ${PROJECT_ROOT}/bin/scheduler.sh..."
cat > "$SERVICE_PATH" << UNITEOF
[Unit]
Description=WEF - Calendrier natif (tick de bin/scheduler.sh)

[Service]
Type=oneshot
WorkingDirectory=${PROJECT_ROOT}
ExecStart=${PROJECT_ROOT}/bin/scheduler.sh
User=root
UNITEOF

cat > "$TIMER_PATH" << 'TIMEREOF'
[Unit]
Description=Declenche le calendrier WEF toutes les 60 secondes

[Timer]
OnBootSec=30s
OnUnitActiveSec=60s
# AccuracySec serre (defaut systemd = 1 min, qui peut faire deriver le
# tick au-dela de la bonne minute - voir lib/cron_match.sh : un tick qui
# tombe dans la MAUVAISE minute manque reellement l'echeance, comme un
# vrai cron).
AccuracySec=1s

[Install]
WantedBy=timers.target
TIMEREOF

echo "[INFRA_010_SCHEDULER_INSTALL] Unites ecrites (${SERVICE_PATH}, ${TIMER_PATH})."
systemctl daemon-reload
systemctl enable --now wef-scheduler.timer

if ! systemctl is-active wef-scheduler.timer >/dev/null 2>&1; then
  echo "[INFRA_010_SCHEDULER_INSTALL] ERREUR : wef-scheduler.timer n'est pas actif apres activation." >&2
  systemctl status wef-scheduler.timer --no-pager >&2 || true
  exit 1
fi

echo "[INFRA_010_SCHEDULER_INSTALL] OK (wef-scheduler.timer actif, tick toutes les 60s - voir journalctl -t wef-scheduler, schedules.csv pour la liste des jobs planifies)."
exit 0
