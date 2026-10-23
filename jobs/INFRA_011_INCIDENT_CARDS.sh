#!/bin/bash
# INFRA_011_INCIDENT_CARDS - WEF_INFRA_RUN_INCIDENTCARDS
#
# AJOUTE LE 2026-10-18. Jusqu'ici, bin/incidents.sh (Registre d'Incidents,
# ITIL 4) devait etre lance a la main par un operateur qui pense a le
# faire - rien ne garantit que ce soit le cas, exactement le risque que
# INFRA_004_HEALTH_GUARDIAN.sh corrige deja pour la supervision continue.
# Ce job ferme le meme ecart pour les fiches d'incident : il appelle
# bin/incidents.sh (logique UNIQUE, jamais dupliquee ici) a cadence
# reguliere via schedules.csv, pour que le registre et les fiches
# individuelles restent a jour sans dependre de la memoire de
# l'operateur - meme discipline que tout le reste de l'usine.
#
# [PLANIFIE UNIQUEMENT via schedules.csv] : IN_COND=INCIDENT_CARDS_SCHEDULE_GATE
# n'est produit par aucun job - jamais eligible via la resolution
# automatique de dependances d'orchestrator.sh (meme motif que
# WAZ_062_NMAP_ROGUE_DEVICE). OUT_COND=NONE : jamais gele, chaque
# execution planifiee est independante (comportement RUN, pas BUILD).
#
# Togglable (INCIDENT_CARDS_ENABLED, vars.conf) - meme principe que
# l'archivage a froid (ES_COLD_ARCHIVE_ENABLED) : un client peut ne pas
# vouloir de cette generation automatique - desactive, ce job ne fait
# rien et ne consomme aucune ressource (bin/incidents.sh lui-meme reste
# utilisable a la main dans tous les cas, cette desactivation ne
# concerne que l'automatisation planifiee).
set -uo pipefail
source "$VARS_FILE"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ "${INCIDENT_CARDS_ENABLED:-true}" != "true" ]; then
  echo "[INFRA_011_INCIDENT_CARDS] Generation automatique des fiches d'incident desactivee (INCIDENT_CARDS_ENABLED=false)."
  echo "[INFRA_011_INCIDENT_CARDS] OK."
  exit 0
fi

echo "[INFRA_011_INCIDENT_CARDS] Derivation du registre d'incidents + fiches individuelles depuis l'historique local de cette machine..."
if ! bash "$HERE/bin/incidents.sh"; then
  echo "[INFRA_011_INCIDENT_CARDS] ERREUR : bin/incidents.sh a echoue." >&2
  exit 1
fi

echo "[INFRA_011_INCIDENT_CARDS] OK."
exit 0
