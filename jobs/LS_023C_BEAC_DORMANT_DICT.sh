#!/bin/bash
# LS_023C_BEAC_DORMANT_DICT - WEF_LS_RUN_BEACDORMDICT
#
# CONSTRUIT LE 2026-10-05. Ce job etait declare dans jobs_table.csv
# depuis le 13/09 mais son script n'avait jamais ete ecrit - jamais
# execute, aucun state/LS_BEAC_DORMANT_DICT_OK.ok. Trouve en auditant
# pourquoi aucune alerte "fraude sur compte dormant" n'existait
# reellement malgre la ligne Architecture/Cartographie correspondante.
#
# Exporte DORMANT_ACCOUNTS (vars.conf) vers un dictionnaire Logstash
# (YAML, consomme par le filtre translate de LS_023D_BEAC_DORMANT_CORRELATION)
# - une seule source de verite (vars.conf), jamais une liste dupliquee
# dans le filtre lui-meme. Rejouable a chaque changement de
# DORMANT_ACCOUNTS (le filtre translate relit ce fichier seul, sans
# jamais redemarrer Logstash - voir refresh_interval dans LS_023D).
set -uo pipefail
source "$VARS_FILE"

DICT_DIR="/etc/logstash/dictionaries"
DICT_FILE="${DICT_DIR}/dormant_accounts.yml"
mkdir -p "$DICT_DIR"

DORMANT_ACCOUNTS="${DORMANT_ACCOUNTS:-}"
if [ -z "$DORMANT_ACCOUNTS" ]; then
  echo "[LS_023C_BEAC_DORMANT_DICT] AVERTISSEMENT : DORMANT_ACCOUNTS est vide dans vars.conf - dictionnaire ecrit vide, aucun compte ne sera jamais qualifie dormant." >&2
fi

TMP_FILE="$(mktemp)"
{
  echo "# Genere automatiquement par LS_023C_BEAC_DORMANT_DICT.sh depuis DORMANT_ACCOUNTS (vars.conf)."
  echo "# NE PAS EDITER A LA MAIN - changez vars.conf puis rejouez ce job."
  IFS=',' read -ra ACCOUNTS <<< "$DORMANT_ACCOUNTS"
  for acct in "${ACCOUNTS[@]}"; do
    acct="$(echo "$acct" | xargs)"
    [ -n "$acct" ] && echo "\"${acct}\": \"true\""
  done
} > "$TMP_FILE"

mv "$TMP_FILE" "$DICT_FILE"
chown root:logstash "$DICT_FILE" 2>/dev/null || true
chmod 644 "$DICT_FILE"

COUNT=$(grep -c ': "true"' "$DICT_FILE")
if [ -n "$DORMANT_ACCOUNTS" ] && [ "$COUNT" -eq 0 ]; then
  echo "[LS_023C_BEAC_DORMANT_DICT] ERREUR : DORMANT_ACCOUNTS non vide mais aucune entree ecrite dans ${DICT_FILE}." >&2
  exit 1
fi

echo "[LS_023C_BEAC_DORMANT_DICT] OK. ${COUNT} compte(s) dormant(s) ecrit(s) dans ${DICT_FILE}."
exit 0
