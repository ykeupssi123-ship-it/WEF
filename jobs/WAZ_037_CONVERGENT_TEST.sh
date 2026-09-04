#!/bin/bash
# WAZ_037_CONVERGENT_TEST - WEF_WAZ_RUN_INJECTCNVRGN
# Injecte une alerte reelle et verifie qu'elle ressort bien cote
# Elasticsearch/Kibana (preuve que le mode convergent route correctement).
#
# REECRIT EN ENTIER LE 2026-08-31 - l'ancienne version injectait un
# simple "logger" generique puis cherchait dans un index "wazuh-alerts-*"
# qui n'existait meme pas cote Elasticsearch sous l'ancien mecanisme
# <syslog_output> (celui-ci alimentait "log-*", jamais "wazuh-alerts-*") -
# le test ne pouvait donc jamais reellement passer, seulement produire un
# AVERTISSEMENT tolerant (jamais un echec dur, jamais remarque). Corrige
# avec le meme constat, la meme solution, que le canari WAZ_041
# (2026-08-31, meme jour) : un "logger" generique ne genere aucune
# alerte Wazuh persistee (log_alert_level=3, aucune regle par defaut ne
# correspond) - reutilise ici la regle dediee id=100101 (WEF_CANARY_TEST,
# posee idempotemment si absente) et interroge desormais le VRAI index
# cible du nouveau pipeline (WAZ_035_MODE_CONVERGENT.sh) : wazuh-alerts-4.x-*
# cote Elasticsearch.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
source "$PROJECT_ROOT/jobs/lib/es_admin_curl.sh"

RULES_FILE="/var/ossec/etc/rules/local_rules.xml"
if ! grep -q 'id="100101"' "$RULES_FILE" 2>/dev/null; then
  echo "[WAZ_037_CONVERGENT_TEST] Pose de la regle dediee au canari (id 100101, niveau 3, absente a ce stade de la chaine)..."
  sed -i 's#</group>#  <rule id="100101" level="3">\n    <match>WEF_CANARY_TEST</match>\n    <description>Test d'"'"'alerte synthetique quotidien de l'"'"'usine (WAZ_041_ALERT_CANARY) - ignorer, jamais un incident reel.</description>\n    <group>canary,</group>\n  </rule>\n</group>#' "$RULES_FILE"
  systemctl restart wazuh-manager 2>/dev/null || true
  if ! wait_for_service_active wazuh-manager 120 5; then
    echo "[WAZ_037_CONVERGENT_TEST] ERREUR : wazuh-manager n'a pas redemarre proprement apres la pose de la regle du canari." >&2
    exit 1
  fi
fi

CANARY_ID="$(date +%s)-$$-convergent"
echo "[WAZ_037_CONVERGENT_TEST] Injection d'une alerte de test reelle (id=${CANARY_ID})..."
logger -t wazuh-canary-test "WEF_CANARY_TEST id=${CANARY_ID} - test de bascule convergente, ignorer"

# CORRIGE LE 2026-08-31 (premier test en direct de la bascule reelle) :
# un simple "sleep 30" fixe suivi d'un seul essai echouait de facon
# reproductible juste apres une bascule fraiche - WAZ_035, juste avant
# ce job dans la chaine, redemarre logstash, et "wait_for_service_active"
# confirme seulement que l'UNITE SYSTEMD est active, jamais que le
# PIPELINE "wazuh-alerts" a lui-meme fini son propre demarrage interne
# (JVM + chargement du pipeline + ouverture du fichier suivi) - constate
# en reel dans logstash-plain.log : la fenetre de 30s de ce job s'etait
# deja ecoulee AVANT que le pipeline n'ait meme commence a lire
# alerts.json. Corrige par un sondage repete (meme discipline que
# WAZ_044_VD_SAFE_RETRY.sh) au lieu d'un delai fixe parie a l'avance.
echo "[WAZ_037_CONVERGENT_TEST] Verification presence dans Elasticsearch (wazuh-alerts-4.x-*, jusqu'a 90s)..."
FOUND=0
for i in $(seq 1 9); do
  sleep 10
  RESULT=$(es_admin_curl "https://127.0.0.1:${ES_PORT}/wazuh-alerts-4.x-*/_search?q=WEF_CANARY_TEST+AND+${CANARY_ID}" 2>/dev/null || echo "")
  if echo "$RESULT" | grep -q "${CANARY_ID}"; then
    FOUND=1
    break
  fi
done
if [ "$FOUND" -eq 1 ]; then
  echo "[WAZ_037_CONVERGENT_TEST] Alerte retrouvee dans Elasticsearch. Mode convergent valide de bout en bout."
else
  echo "[WAZ_037_CONVERGENT_TEST] ERREUR : alerte introuvable dans Elasticsearch apres 90s - le routage convergent ne fonctionne pas." >&2
  exit 1
fi
echo "[WAZ_037_CONVERGENT_TEST] OK."
exit 0
