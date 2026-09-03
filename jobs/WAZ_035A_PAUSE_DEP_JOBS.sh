#!/bin/bash
# WAZ_035A_PAUSE_DEP_JOBS - WEF_WAZ_BLD_PAUSEIDXJOBS
# Mise en veille : pause, le temps de la bascule vers Kibana, des jobs
# qui presupposent wazuh-indexer actif en permanence.
#
# AJOUTE LE 2026-09-03 (refonte demandee par l'utilisateur, voir
# docs/JOURNAL_TECHNIQUE.md). L'ancien WAZ_035_MODE_CONVERGENT.sh (avant
# cette refonte) ne coupait JAMAIS wazuh-indexer, precisement pour ne
# pas casser ces jobs (voir son historique git). La refonte demandee
# rend le mode Kibana EXCLUSIF (indexeur+dashboard reellement arretes,
# job WAZ_035D plus loin dans la chaine) - il faut donc explicitement
# neutraliser ce qui en depend, sinon ces jobs echoueraient/alerteraient
# a tort pendant toute la duree du mode Kibana :
#   - WAZ_014D_ALERTS_RETENTION (politique ISM de retention)
#   - WAZ_014E_INDEXER_CONNECTOR (connecteur natif inventaire/vulns)
#   - WAZ_042_INDEXER_UNLOCK (verrous flood-stage)
#   - WAZ_043_DASHBOARD_FIELDS_REFRESH (cache de champs du Dashboard)
# Ajoutes a SKIP_JOBS (vars.conf) - ne les empeche pas d'etre DEJA .ok
# (ils ne seraient de toute facon pas rejoues), mais empeche un
# reforcage accidentel ou un futur redeploiement partiel de les relancer
# pendant que l'indexeur est bas.
#
# CAS A PART : INFRA_004_HEALTH_GUARDIAN n'est PAS un job reexecute par
# l'orchestrateur en continu - c'est un INSTALLATEUR (execute une seule
# fois) d'un timer systemd independant (wef-health-guardian.timer, toutes
# les 5 min) qui, lui, ne consulte jamais SKIP_JOBS. L'ajouter a
# SKIP_JOBS n'aurait donc aucun effet reel - le timer est directement
# suspendu ici via systemctl.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
source "$PROJECT_ROOT/jobs/lib/skip_jobs_toggle.sh"

DEP_JOBS="WAZ_014D_ALERTS_RETENTION,WAZ_014E_INDEXER_CONNECTOR,WAZ_042_INDEXER_UNLOCK,WAZ_043_DASHBOARD_FIELDS_REFRESH"

echo "[WAZ_035A_PAUSE_DEP_JOBS] Ajout de ${DEP_JOBS} a SKIP_JOBS..."
add_jobs_to_skip_list "$DEP_JOBS" || exit 1

echo "[WAZ_035A_PAUSE_DEP_JOBS] Suspension du timer systemd wef-health-guardian (independant de SKIP_JOBS)..."
if systemctl list-unit-files wef-health-guardian.timer >/dev/null 2>&1; then
  systemctl stop wef-health-guardian.timer 2>/dev/null || true
  if systemctl is-active --quiet wef-health-guardian.timer; then
    echo "[WAZ_035A_PAUSE_DEP_JOBS] ERREUR : wef-health-guardian.timer toujours actif apres 'systemctl stop'." >&2
    exit 1
  fi
else
  echo "[WAZ_035A_PAUSE_DEP_JOBS] wef-health-guardian.timer absent (INFRA_004 n'a peut-etre pas encore tourne) - rien a suspendre."
fi

echo "[WAZ_035A_PAUSE_DEP_JOBS] OK."
exit 0
