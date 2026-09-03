#!/bin/bash
# WAZ_039D_RESUME_DEP_JOBS - WEF_WAZ_RUN_RESUMEIDXJOBS
# Reveil : retire de SKIP_JOBS les jobs mis en pause par
# WAZ_035A_PAUSE_DEP_JOBS et redemarre le timer wef-health-guardian.
# Dernier job de la cascade "retour vers Wazuh" - ecrit le marqueur
# officiel de bascule (WAZ_ALERTS_ROUTE.state) une fois tout confirme.
#
# AJOUTE LE 2026-09-03 (refonte demandee par l'utilisateur, voir
# docs/JOURNAL_TECHNIQUE.md). Miroir exact de WAZ_035A_PAUSE_DEP_JOBS.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
source "$PROJECT_ROOT/jobs/lib/skip_jobs_toggle.sh"

DEP_JOBS="WAZ_014D_ALERTS_RETENTION,WAZ_014E_INDEXER_CONNECTOR,WAZ_042_INDEXER_UNLOCK,WAZ_043_DASHBOARD_FIELDS_REFRESH"
ROUTE_STATE_FILE="${STATE_DIR}/WAZ_ALERTS_ROUTE.state"

echo "[WAZ_039D_RESUME_DEP_JOBS] Retrait de ${DEP_JOBS} de SKIP_JOBS..."
remove_jobs_from_skip_list "$DEP_JOBS" || exit 1

echo "[WAZ_039D_RESUME_DEP_JOBS] Reactivation du timer systemd wef-health-guardian..."
# CORRIGE LE 2026-09-03 (meme diagnostic reel que WAZ_035A_PAUSE_DEP_JOBS.sh,
# meme premier test en direct de la refonte) : "systemctl list-unit-files
# <nom>" n'est pas un indicateur fiable d'existence (code 0 meme absent).
# Verifie directement le fichier d'unite sur disque.
if [ -f /etc/systemd/system/wef-health-guardian.timer ]; then
  systemctl start wef-health-guardian.timer 2>/dev/null || true
  if ! systemctl is-active --quiet wef-health-guardian.timer; then
    echo "[WAZ_039D_RESUME_DEP_JOBS] ERREUR : wef-health-guardian.timer toujours inactif apres 'systemctl start'." >&2
    exit 1
  fi
else
  echo "[WAZ_039D_RESUME_DEP_JOBS] wef-health-guardian.timer absent (INFRA_004 n'a pas encore tourne sur cette VM) - rien a reactiver."
fi

echo "INDEXER" > "$ROUTE_STATE_FILE"
echo "[WAZ_039D_RESUME_DEP_JOBS] Bascule confirmee : alertes Wazuh -> wazuh-indexer, jobs dependants et surveillance reactives."
echo "[WAZ_039D_RESUME_DEP_JOBS] OK."
exit 0
