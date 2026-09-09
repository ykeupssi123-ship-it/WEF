#!/bin/bash
# summary.sh - Tableau de bord final : URLs, identifiants et scenarios
# prets a l'emploi, une fois le deploiement termine.
#
# AJOUTE LE 2026-09-09 (demande explicite : ne plus vouloir revoir le
# defilement des ~270 jobs a chaque fin de deploiement - juste un
# tableau exploitable). Lit UNIQUEMENT l'etat REEL de la machine au
# moment de l'appel (vars.conf, secrets/, state/, fichiers de config
# live) - jamais une valeur supposee/en dur, pour rester juste meme si
# vars.conf a ete personnalise ou si un mot de passe n'a pas encore ete
# genere (job pas encore passe sur cette machine).
#
# A lancer a tout moment (pas seulement en fin de chaine) :
#   $APP_BIN/summary.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"
export VARS_FILE="${VARS_FILE:-$HERE/vars.conf}"
source "$VARS_FILE"

pw_or() {
  if [ -f "$1" ] && [ -s "$1" ]; then
    cat "$1"
  else
    echo "(non genere - job pas encore passe)"
  fi
}

echo "===================================================================="
echo " ${PROJECT_NAME:-WAZ_ELK_FACTORY} - TABLEAU DE BORD"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo "===================================================================="
echo ""

# CORRIGE LE 2026-09-09 (demande explicite : audit de conformite
# ELK_HOST/AGENT_HOST) : ce tableau (URLs/mots de passe ES/Kibana/Wazuh
# Dashboard) n'a jamais eu de sens sur un AGENT_HOST - aucun de ces
# services n'y tourne (seulement Filebeat/Metricbeat/agent Wazuh, sans
# UI/API propre a resumer de la meme facon). bin/monitor.sh filtre deja
# par ROLE (voir son propre code) - summary.sh ne le faisait pas,
# affichant a tort des URLs/mots de passe de services absents de cette
# machine. Corrige : branche dediee, courte et honnete, pour ce role.
if [ "${ROLE:-}" = "AGENT_HOST" ]; then
  echo "--- AGENT_HOST : ${AGENT_NAME:-(non defini)} ---"
  echo "Composants actifs : ${AGENT_COMPONENTS:-(aucun)}"
  echo "Machine ELK_HOST cible : ${FACTORY_HOST_IP:-(non defini)}"
  echo ""
  echo "--- ETAT DES SERVICES (uniquement les composants actives) ---"
  IFS=',' read -ra ENABLED_COMPS <<< "${AGENT_COMPONENTS:-}"
  for comp in "${ENABLED_COMPS[@]}"; do
    case "$comp" in
      FILEBEAT)
        svc="filebeat" ;;
      METRICBEAT)
        svc="metricbeat" ;;
      WAZUH_AGENT)
        svc="wazuh-agent" ;;
      *)
        continue ;;
    esac
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
      printf "%-14s actif\n" "$svc"
    else
      printf "%-14s INACTIF (verifier : systemctl status %s)\n" "$svc" "$svc"
    fi
  done
  echo ""
  echo "--- SCENARIOS ---"
  echo "Historique d'un job        : \$APP_BIN/history.sh <JOB_ID>"
  echo "Monitoring en direct (CLI) : \$APP_BIN/monitor.sh"
  echo "Aucune URL/mot de passe a afficher ici - les tableaux de bord"
  echo "(Wazuh Dashboard/Kibana) vivent sur ELK_HOST (\$FACTORY_HOST_IP),"
  echo "jamais sur un AGENT_HOST."
  echo "===================================================================="
  exit 0
fi

echo "--- ACCES ---"
printf "%-22s %-42s %-16s %s\n" "SERVICE" "URL" "UTILISATEUR" "MOT DE PASSE"
printf "%-22s %-42s %-16s %s\n" "----------------------" "------------------------------------------" "----------------" "------------"

# Wazuh Dashboard : port reel lu dans sa propre config (443 par defaut
# si le fichier est absent ou ne precise rien - jamais suppose en dur).
WAZ_DASH_PORT=$(grep -oP '^server\.port:\s*\K[0-9]+' /etc/wazuh-dashboard/opensearch_dashboards.yml 2>/dev/null || echo 443)
printf "%-22s %-42s %-16s %s\n" "Wazuh Dashboard" "https://${FACTORY_HOST_IP}:${WAZ_DASH_PORT}/" "${WAZ_INDEXER_ADMIN_USER}" "$(pw_or "$WAZ_INDEXER_ADMIN_PASSWORD_FILE")"

printf "%-22s %-42s %-16s %s\n" "Kibana" "https://${FACTORY_HOST_IP}:${KB_PORT}/" "elastic" "$(pw_or "${STATE_DIR}/es_bootstrap_password.secret")"

printf "%-22s %-42s %-16s %s\n" "Elasticsearch (API)" "https://${FACTORY_HOST_IP}:${ES_PORT}/" "elastic" "$(pw_or "${STATE_DIR}/es_bootstrap_password.secret")"

printf "%-22s %-42s %-16s %s\n" "Wazuh Indexer (API)" "https://${FACTORY_HOST_IP}:${WAZ_INDEXER_PORT}/" "${WAZ_INDEXER_ADMIN_USER}" "$(pw_or "$WAZ_INDEXER_ADMIN_PASSWORD_FILE")"

printf "%-22s %-42s %-16s %s\n" "Wazuh API" "https://${FACTORY_HOST_IP}:${WAZ_API_PORT}/" "${WAZ_API_USER}" "$(pw_or "$WAZ_API_PASSWORD_FILE")"

printf "%-22s %-42s %-16s %s\n" "Suivi orchestrateur" "http://${FACTORY_HOST_IP}:${DASHBOARD_PORT}/" "(lecture seule)" "-"

echo ""
echo "--- MODE ACTIF (Wazuh Dashboard <-> Kibana, exclusif l'un de l'autre) ---"
if systemctl is-active --quiet wazuh-dashboard 2>/dev/null; then
  echo "Wazuh Dashboard (mode souverain natif)"
elif systemctl is-active --quiet kibana 2>/dev/null; then
  echo "Kibana (mode convergent ELK)"
else
  echo "Indetermine - verifier manuellement : systemctl status wazuh-dashboard kibana"
fi

echo ""
echo "--- SCENARIOS PRETS A L'EMPLOI (\$APP_BIN/order.sh <JOB_ID> \"<raison>\") ---"
echo "Basculer vers Kibana          : \$APP_BIN/order.sh WAZ_035_KIBANA_TRIGGER \"demo bascule Kibana\""
echo "Basculer vers Wazuh Dashboard : \$APP_BIN/order.sh WAZ_039_WAZUH_TRIGGER \"demo retour Wazuh Dashboard\""
echo "Remplissage VISIBLE (demo)    : \$APP_BIN/order.sh WAZ_048_SEED_INDEXER_LIVE \"demo remplissage visible\"  (ou WAZ_049_SEED_ES_LIVE selon le mode actif - ${WAZ_DEMO_SEED_COUNT:-100} documents, 1 toutes les ${WAZ_DEMO_SEED_INTERVAL_SEC:-1}s, a regarder arriver dans le tableau de bord)"
echo "Charger un GROS volume (test) : \$APP_BIN/order.sh WAZ_045A_SEED_INDEXER_DATA \"demo\"  (ou WAZ_045B_SEED_ES_DATA - instantane, pour tester la migration, pas pour regarder)"
echo "Purger les donnees de demo    : \$APP_BIN/order.sh WAZ_046_PURGE_INDEXER_DATA \"fin demo\"  (ou WAZ_047_PURGE_ES_DATA selon le mode actif)"
echo "Historique d'un job           : \$APP_BIN/history.sh <JOB_ID>"
echo "Monitoring en direct (CLI)    : \$APP_BIN/monitor.sh"
echo "===================================================================="
exit 0
