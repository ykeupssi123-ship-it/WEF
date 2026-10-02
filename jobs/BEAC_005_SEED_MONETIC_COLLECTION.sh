#!/bin/bash
# BEAC_005_SEED_MONETIC_COLLECTION - WEF_BEAC_RUN_SEEDMONETIC
#
# AJOUTE LE 2026-09-30 (remplace BEAC_005_SEED_THIRDCOUNTRY_RELAY,
# annule sur demande explicite - "contournement par un pays tiers" est
# abandonne). Repond a deux objectifs Architecture a la fois :
# "Collecte des donnees financieres et monetiques" (Applications, ancien
# emplacement de "Supervision applicative unifiee"/AnkrrWEF - retiree du
# dossier) et "Fraude sur compte dormant" (Applications > Conformite
# financiere, ancien emplacement de "Contournement par un pays tiers").
#
# MECANISME : meme fichier/index que BEAC_001. La fonction
# seed_monetic_collection_file (jobs/lib/beac_scenario_tools.sh) genere
# un flux de transactions financieres et monetiques (DAB, GAB, TPE,
# GUICHET, VIREMENT_EN_LIGNE) majoritairement normales, PLUS une
# transaction REUSSIE GARANTIE (jamais un tirage au sort) pour CHAQUE
# compte declare dans DORMANT_ACCOUNTS (vars.conf).
#
# REFONDU LE 2026-10-01 (demande explicite : "l'alerte ne doit pas
# monter directement... c'est Logstash qui doit faire la correlation") :
# ce job N'ECRIT PLUS LE JUGEMENT lui-meme - les transactions ecrites
# sont BRUTES (type_evenement=transaction_brute, aucun detection_type/
# niveau_alerte/statut_compte/statut_traitement). C'est desormais
# jobs/LS_023D_BEAC_DORMANT_CORRELATION.sh (filtre Logstash translate +
# condition, lisant le dictionnaire ecrit par
# jobs/LS_023C_BEAC_DORMANT_DICT.sh) qui determine REELLEMENT si une
# transaction est une fraude - ce job-ci ne "joue" plus le role d'un
# logiciel de detection, c'est desormais le PIPELINE LOGSTASH qui
# detecte pour de vrai. Une ligne tapee a la main (voir Exploitation,
# DATA-08) passe par exactement le meme filtre, aucun traitement special.
#
# JOUE SUR AGENT_HOST (VM2), meme raison que BEAC_001 : les donnees
# naissent sur une machine cliente et remontent via Filebeat.
#
# MANUEL UNIQUEMENT (IN_COND=WAZ_PURGE_MANUAL_GATE, jamais satisfaite
# ailleurs - meme gate que BEAC_001) :
#   $APP_BIN/order.sh BEAC_005_SEED_MONETIC_COLLECTION "demo collecte monetique / fraude compte dormant"
#
# PREALABLE : LS_023B_BEAC_FILTER, LS_023C_BEAC_DORMANT_DICT et
# LS_023D_BEAC_DORMANT_CORRELATION doivent avoir tourne sur ELK_HOST
# (chaine complete desormais exigee avant LS_024 dans jobs_table.csv).
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
source "$PROJECT_ROOT/jobs/lib/beac_scenario_tools.sh"

SEED_INTERVAL="${WAZ_DEMO_SEED_INTERVAL_SEC:-1}"
DORMANT_ACCOUNTS="${DORMANT_ACCOUNTS:-}"
if [ -z "$DORMANT_ACCOUNTS" ]; then
  echo "[BEAC_005_SEED_MONETIC_COLLECTION] AVERTISSEMENT : DORMANT_ACCOUNTS est vide dans vars.conf - aucune fraude compte dormant garantie, seulement du volume normal." >&2
fi

echo "[BEAC_005_SEED_MONETIC_COLLECTION] Ecriture de transactions monetiques (${LCBFT_SEED_MIN_COUNT}-${LCBFT_SEED_MAX_COUNT} normales + $(echo "$DORMANT_ACCOUNTS" | tr ',' '\n' | grep -c .) fraude(s) garantie(s), 1 toutes les ${SEED_INTERVAL}s) dans ${LCBFT_LOG_FILE}..."
SEED_LOG="$(mktemp)"
seed_monetic_collection_file "$LCBFT_LOG_FILE" "$LCBFT_SEED_MIN_COUNT" "$LCBFT_SEED_MAX_COUNT" "$SEED_INTERVAL" "$DORMANT_ACCOUNTS" > "$SEED_LOG" 2>&1
SEED_EXIT=$?
cat "$SEED_LOG"
if [ $SEED_EXIT -ne 0 ]; then
  echo "[BEAC_005_SEED_MONETIC_COLLECTION] ERREUR : l'ecriture a echoue (voir sortie ci-dessus)." >&2
  rm -f "$SEED_LOG"
  exit 1
fi
rm -f "$SEED_LOG"

echo "[BEAC_005_SEED_MONETIC_COLLECTION] OK. Transactions brutes ecrites - Logstash determine seul lesquelles sont des fraudes. Filtrer le dashboard sur detection_type: FRAUDE_COMPTE_DORMANT (niveau_alerte: 13, statut_traitement: SOUS_EMBARGO) une fois la correlation appliquee."
exit 0
