#!/bin/bash
# WAZ_014C_ALERTS_TEMPLATE - WEF_WAZ_BLD_ALERTSTMPL - Modele d'index pour
# wazuh-alerts-4.x-* / wazuh-archives-4.x-*
#
# AJOUTE LE 2026-08-31 (incident reel : le controle de sante du Wazuh
# Dashboard, verifie directement dans le navigateur par l'utilisateur -
# https://dashboard.wef.local/app/wz-home#/health-check - signale en
# rouge "[Alerts index pattern] No template found for the selected
# index-pattern title [wazuh-alerts-*]"). Confirme en reel :
# `_cat/templates` sur wazuh-indexer ne liste que "wazuh-statistics" et
# "wazuh-agent" (crees automatiquement par le manager/API Wazuh pour ses
# propres besoins de supervision) - AUCUN modele pour les alertes
# elles-memes. Cause reelle : le connecteur natif Wazuh (qui installe ce
# modele automatiquement) n'est jamais utilise dans cette usine -
# l'acheminement des alertes passe par un pipeline Logstash dedie
# (WAZ_014B), qui ecrit dans wazuh-indexer via une simple API _doc, sans
# jamais poser le modele au prealable. Sans lui, les index quotidiens
# (wazuh-alerts-4.x-AAAA.MM.JJ) sont crees avec un mappage DYNAMIQUE
# generique - champs mal types (dates, IP, sous-champs .keyword absents),
# ce qui casse les tableaux de bord et visualisations Wazuh qui
# supposent le mappage officiel.
#
# SOURCE DU MODELE : templates/wazuh-alerts-template.json (a cote de ce
# script, PROJECT_ROOT/templates/) - copie EXACTE du fichier officiel
# livre par le paquet filebeat lors du tout premier essai d'ingestion de
# cette usine (voir l'en-tete de WAZ_014B_ALERTS_TO_INDEXER.sh, "PREMIER
# ESSAI abandonne"), dont les index_patterns ("wazuh-alerts-4.x-*",
# "wazuh-archives-4.x-*") correspondent EXACTEMENT au schema reel utilise
# ici. Volontairement copie DANS le projet plutot que lu depuis
# /etc/filebeat/ (chemin residuel de cet essai abandonne, absent sur une
# VM neuve qui ne rejouerait jamais cette tentative) : ce job ne depend
# plus de rien d'externe pour fonctionner sur un deploiement a froid.
#
# API LEGACY (_template, pas _index_template) : format du fichier
# source lui-meme ("order"/"index_patterns" au premier niveau, pas
# imbrique dans "template") - c'est le format legacy Elasticsearch,
# toujours supporte par wazuh-indexer (base OpenSearch), et c'est la
# methode documentee officiellement par Wazuh pour ce fichier precis.
#
# CORRIGE LE 2026-08-31 (meme jour, incident reel decouvert en
# supprimant/recreant l'index pour appliquer ce modele pour de bon -
# jamais suppose correct sans reessayer un vrai flux d'alertes apres
# coup) : le fichier officiel, tel que livre, definit "host" comme
# simple "type": "keyword" - or les alertes REELLEMENT generees par
# cette installation (confirme par lecture directe de alerts.json) pour
# tout evenement source de journald/syslog portent "host" comme un OBJET
# ({"name": "..."}), jamais une chaine simple. Consequence reelle
# observee : Logstash rejetait ces documents en boucle (HTTP 400,
# "mapper_parsing_exception ... Can't get text on a START_OBJECT"),
# perdus silencieusement (jamais retentes - retry_non_idempotent ne
# couvre pas les codes 4xx, permanents par nature). Corrige : "host" est
# desormais un objet avec sous-champ "name" (keyword) dans
# templates/wazuh-alerts-template.json - le fichier "officiel" livre par
# le paquet n'est donc PAS pris pour argent comptant, verifie ligne a
# ligne contre le comportement reel de CETTE version installee (Wazuh
# 4.14.7) et corrige ou il divergeait.
#
# ORDRE REEL IMPORTANT : ce job doit poser le modele AVANT que
# WAZ_014B ne commence a ecrire des alertes - un modele pose APRES la
# creation d'un index n'affecte jamais retroactivement le mappage deja
# fige de cet index (seuls les FUTURS index quotidiens en beneficient).
# WAZ_014B_ALERTS_TO_INDEXER (IN_COND, jobs_table.csv) attend desormais
# WAZ_ALERTS_TEMPLATE_OK avant de demarrer.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

WAZUH_INDEXER_ADMIN_PW="$(read_or_generate_secret "$WAZ_INDEXER_ADMIN_PASSWORD_FILE" non)" || exit 1
WAZ_INDEXER_PORT="${WAZ_INDEXER_PORT:-9200}"
TEMPLATE_FILE="${PROJECT_ROOT}/templates/wazuh-alerts-template.json"

[ -f "$TEMPLATE_FILE" ] || { echo "[WAZ_014C] ERREUR : ${TEMPLATE_FILE} introuvable." >&2; exit 1; }

echo "[WAZ_014C] Pose du modele d'index 'wazuh' (wazuh-alerts-4.x-*/wazuh-archives-4.x-*)..."
HTTP_CODE=$(curl -sk -u "${WAZ_INDEXER_ADMIN_USER}:${WAZUH_INDEXER_ADMIN_PW}" \
  -X PUT "https://127.0.0.1:${WAZ_INDEXER_PORT}/_template/wazuh" \
  -H 'Content-Type: application/json' \
  --data-binary "@${TEMPLATE_FILE}" \
  -o "${WORK_TMP_DIR}/waz014c_put.json" -w '%{http_code}')

if [ "$HTTP_CODE" != "200" ]; then
  echo "[WAZ_014C] ERREUR : pose du modele en echec (HTTP ${HTTP_CODE}), voir ${WORK_TMP_DIR}/waz014c_put.json" >&2
  cat "${WORK_TMP_DIR}/waz014c_put.json" >&2 2>/dev/null || true
  exit 1
fi

echo "[WAZ_014C] Verification reelle (le modele doit apparaitre dans _cat/templates)..."
if ! curl -sk -u "${WAZ_INDEXER_ADMIN_USER}:${WAZUH_INDEXER_ADMIN_PW}" \
  "https://127.0.0.1:${WAZ_INDEXER_PORT}/_cat/templates?v" | grep -q '^wazuh '; then
  echo "[WAZ_014C] ERREUR : le modele 'wazuh' n'apparait pas dans _cat/templates apres la pose." >&2
  exit 1
fi

rm -f "${WORK_TMP_DIR}/waz014c_put.json"
echo "[WAZ_014C] OK (modele 'wazuh' confirme present)."
exit 0
