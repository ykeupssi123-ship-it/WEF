#!/bin/bash
# WAZ_040_KIBANA_SILENT - WEF_WAZ_RUN_KBSILENT
# Verifie qu'en mode souverain, une NOUVELLE alerte part bien vers
# wazuh-indexer et plus du tout vers Elasticsearch/Kibana (preuve de
# bascule exclusive reelle, pas seulement d'un service eteint).
#
# REECRIT EN ENTIER LE 2026-08-31 - meme constat que WAZ_037_CONVERGENT_
# TEST.sh (voir son en-tete) : l'ancien "logger" generique ne generait
# aucune alerte persistee et interrogeait un index jamais alimente par
# l'ancien mecanisme - le test ne pouvait jamais reellement echouer NI
# reellement reussir. Corrige avec la meme regle dediee id=100101
# (WEF_CANARY_TEST) que WAZ_037/WAZ_041, et une verification a DOUBLE
# sens desormais possible avec un ID unique par execution :
#   (1) la nouvelle alerte DOIT apparaitre dans wazuh-indexer (preuve que
#       le retour en mode souverain route bien les alertes FUTURES) ;
#   (2) elle NE DOIT PAS apparaitre dans Elasticsearch (preuve que
#       l'ecriture y est bien coupee - jamais suppose du seul fait que
#       wazuh-dashboard ait redemarre).
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
source "$PROJECT_ROOT/jobs/lib/es_admin_curl.sh"

WAZUH_INDEXER_ADMIN_PW="$(read_or_generate_secret "$WAZ_INDEXER_ADMIN_PASSWORD_FILE" non)" || exit 1
WAZ_INDEXER_PORT="${WAZ_INDEXER_PORT:-9200}"

# CORRIGE LE 2026-10-05 (bug reel trouve en rejouant la cascade FONC-08
# avant la demo : la regle 100101 ecrite dans local_rules.xml ne
# declenchait JAMAIS - ce fichier n'est pas charge par analysisd sur
# cette installation (confirme le 2026-09-30, voir le commentaire laisse
# dans ce fichier). Redirige vers le meme fichier reellement charge que
# WAZ_025/WAZ_051/WAZ_060/WAZ_061.
RULES_FILE="/var/ossec/ruleset/rules/9950-wef_custom_rules.xml"
mkdir -p "$(dirname "$RULES_FILE")"
[ -f "$RULES_FILE" ] || : > "$RULES_FILE"
MARKER_RULE_101="<!-- WEF_CANARY_RULE (WAZ_040/WAZ_041, genere automatiquement - ne pas editer a la main) -->"
if ! grep -qF "$MARKER_RULE_101" "$RULES_FILE" 2>/dev/null; then
  echo "[WAZ_040_KIBANA_SILENT] Pose de la regle dediee au canari (id 100101, niveau 3, absente a ce stade de la chaine)..."
  {
    echo "$MARKER_RULE_101"
    echo '<group name="canary,">'
    echo '  <rule id="100101" level="3">'
    echo '    <match>WEF_CANARY_TEST</match>'
    echo "    <description>Test d'alerte synthetique quotidien de l'usine (WAZ_041_ALERT_CANARY) - ignorer, jamais un incident reel.</description>"
    echo '  </rule>'
    echo '</group>'
    echo "<!-- WEF_CANARY_RULE_END -->"
  } >> "$RULES_FILE"
  grep -qF "$MARKER_RULE_101" "$RULES_FILE" || { echo "[WAZ_040_KIBANA_SILENT] ERREUR : regle canari absente apres ecriture dans ${RULES_FILE}." >&2; exit 1; }
  chown root:wazuh "$RULES_FILE"
  chmod 640 "$RULES_FILE"
  systemctl restart wazuh-manager 2>/dev/null || true
  if ! wait_for_service_active wazuh-manager 120 5; then
    echo "[WAZ_040_KIBANA_SILENT] ERREUR : wazuh-manager n'a pas redemarre proprement apres la pose de la regle du canari." >&2
    exit 1
  fi
fi

CANARY_ID="$(date +%s)-$$-souverain"
echo "[WAZ_040_KIBANA_SILENT] Injection d'une alerte de controle reelle (id=${CANARY_ID})..."
logger -t wazuh-canary-test "WEF_CANARY_TEST id=${CANARY_ID} - test de bascule souveraine, ignorer"

# CORRIGE LE 2026-08-31 - meme constat reel que WAZ_037_CONVERGENT_TEST.sh
# (voir son en-tete) : le pipeline "wazuh-alerts" de logstash, redemarre
# juste avant par WAZ_039, peut mettre plus de 30s a finir son propre
# demarrage interne malgre une unite systemd deja "active". Sondage
# repete au lieu d'un delai fixe.
echo "[WAZ_040_KIBANA_SILENT] Verification presence dans wazuh-indexer (nouvelle destination attendue, jusqu'a 90s)..."
FOUND=0
for i in $(seq 1 9); do
  sleep 10
  IDXR_RESULT=$(curl -sk -u "${WAZ_INDEXER_ADMIN_USER}:${WAZUH_INDEXER_ADMIN_PW}" \
    "https://127.0.0.1:${WAZ_INDEXER_PORT}/wazuh-alerts-4.x-*/_search?q=WEF_CANARY_TEST+AND+${CANARY_ID}" 2>/dev/null || echo "")
  if echo "$IDXR_RESULT" | grep -q "${CANARY_ID}"; then
    FOUND=1
    break
  fi
done
if [ "$FOUND" -eq 1 ]; then
  echo "[WAZ_040_KIBANA_SILENT] Alerte retrouvee dans wazuh-indexer - retour en mode souverain confirme."
else
  echo "[WAZ_040_KIBANA_SILENT] ERREUR : alerte introuvable dans wazuh-indexer apres 90s - le routage souverain ne fonctionne pas." >&2
  exit 1
fi

echo "[WAZ_040_KIBANA_SILENT] Verification d'absence dans Elasticsearch (aucune nouvelle ecriture attendue)..."
ES_RESULT=$(es_admin_curl "https://127.0.0.1:${ES_PORT}/wazuh-alerts-4.x-*/_search?q=WEF_CANARY_TEST+AND+${CANARY_ID}" 2>/dev/null || echo "")
if echo "$ES_RESULT" | grep -q "${CANARY_ID}"; then
  echo "[WAZ_040_KIBANA_SILENT] ERREUR : cette alerte, pourtant posterieure a la bascule souveraine, est apparue dans Elasticsearch - l'ecriture n'y est PAS coupee." >&2
  exit 1
else
  echo "[WAZ_040_KIBANA_SILENT] Silence confirme cote Elasticsearch/Kibana. Mode souverain etanche."
fi
echo "[WAZ_040_KIBANA_SILENT] OK."
exit 0
