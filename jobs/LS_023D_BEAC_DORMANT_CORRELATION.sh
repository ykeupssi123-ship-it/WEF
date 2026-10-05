#!/bin/bash
# LS_023D_BEAC_DORMANT_CORRELATION - WEF_LS_RUN_BEACDORMCORR
#
# CONSTRUIT LE 2026-10-05 (meme decouverte que LS_023C - jamais
# execute, script absent malgre la ligne jobs_table.csv depuis le
# 13/09, et IN_COND de LS_023C corrige le meme jour : il pointait vers
# LS_BEAC_GLASSFISH_OK, une condition JAMAIS produite puisque
# LS_023E_BEAC_GLASSFISH_UNWRAP.sh n'existe pas non plus - orphelin
# reel qui rendait LS_023C/LS_023D inatteignables par l'orchestrateur
# automatique. Corrige vers LS_BEAC_FILTER_OK (produit par
# LS_023B_BEAC_FILTER, deja reellement execute) : la qualification
# dormant/actif ne depend en rien du canal GlassFish, seulement du
# parsing JSON de base deja fait par LS_023B.
#
# MECANISME REEL (lit le dictionnaire ecrit par LS_023C) : une
# transaction_brute (ecrite par BEAC_001/BEAC_003/BEAC_005, OU tapee a
# la main - Operations, scenario "Fraude sur compte dormant") n'est
# qualifiee FRAUDE_COMPTE_DORMANT QUE si :
#   1. compte_ref figure dans le dictionnaire DORMANT_ACCOUNTS (filtre
#      translate - jamais une comparaison de chaine codee en dur ici)
#   2. ET resultat_operation == "REUSSI" (une tentative qui echoue sur
#      un compte dormant n'est pas le signal recherche - voir
#      seed_monetic_collection_file, jobs/lib/beac_scenario_tools.sh :
#      "le signal n'est pas la tentative, c'est la reussite")
# Sinon : compte dormant mais operation non reussie -> TENTATIVE_REJETEE
# (trace quand meme, jamais silencieux) ; compte non dormant -> ACTIF
# (fallback explicite du translate filter, jamais un champ absent).
set -uo pipefail
source "$VARS_FILE"
echo "[LS_023D_BEAC_DORMANT_CORRELATION] Ecriture du filtre de correlation compte dormant..."
mkdir -p /etc/logstash/conf.d
FILTER_FILE="/etc/logstash/conf.d/13-dormant-correlation.conf"
if [ -e "$FILTER_FILE" ] && lsattr "$FILTER_FILE" 2>/dev/null | grep -q '^....i'; then
  echo "[LS_023D_BEAC_DORMANT_CORRELATION] ${FILTER_FILE} est immuable (deja verrouille par LS_036_FINAL) - deverrouillage temporaire avant reecriture."
  chattr -i "$FILTER_FILE"
fi
cat > "$FILTER_FILE" << 'CONFEOF'
filter {
  if [type_evenement] == "transaction_brute" {
    translate {
      field => "[compte_ref]"
      destination => "[compte_dormant]"
      dictionary_path => "/etc/logstash/dictionaries/dormant_accounts.yml"
      fallback => "false"
      refresh_interval => 60
    }
    if [compte_dormant] == "true" and [resultat_operation] == "REUSSI" {
      mutate {
        add_field => {
          "detection_type" => "FRAUDE_COMPTE_DORMANT"
          "statut_compte" => "DORMANT"
          "statut_traitement" => "SOUS_EMBARGO"
          "niveau_alerte" => "13"
        }
      }
      mutate {
        convert => { "niveau_alerte" => "integer" }
      }
    } else if [compte_dormant] == "true" {
      mutate {
        add_field => {
          "statut_compte" => "DORMANT"
          "statut_traitement" => "TENTATIVE_REJETEE"
        }
      }
    } else {
      mutate {
        add_field => {
          "statut_compte" => "ACTIF"
        }
      }
    }
  }
}
CONFEOF
if ! grep -q 'FRAUDE_COMPTE_DORMANT' "$FILTER_FILE" 2>/dev/null; then
  echo "[LS_023D_BEAC_DORMANT_CORRELATION] ERREUR : ${FILTER_FILE} ne contient pas le filtre attendu apres ecriture - la redirection a echoue silencieusement (fichier toujours immuable ?)." >&2
  exit 1
fi

echo "[LS_023D_BEAC_DORMANT_CORRELATION] Redemarrage de Logstash pour charger le nouveau filtre (config.reload.automatic=false sur cette machine)..."
if ! systemctl restart logstash; then
  echo "[LS_023D_BEAC_DORMANT_CORRELATION] ERREUR : le redemarrage de Logstash a echoue - le filtre est ecrit mais pas encore actif." >&2
  systemctl status logstash --no-pager -l 2>&1 | tail -20 >&2
  exit 1
fi
sleep 5
if ! systemctl is-active --quiet logstash; then
  echo "[LS_023D_BEAC_DORMANT_CORRELATION] ERREUR : Logstash ne reste pas actif apres redemarrage (config invalide ?)." >&2
  journalctl -u logstash --no-pager -n 40 >&2
  exit 1
fi

echo "[LS_023D_BEAC_DORMANT_CORRELATION] OK."
exit 0
