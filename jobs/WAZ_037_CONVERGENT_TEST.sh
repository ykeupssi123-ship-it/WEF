#!/bin/bash
# WAZ_037_CONVERGENT_TEST - WEF_WAZ_RUN_INJECTCNVRGN
# Verifie que le mode convergent route reellement les alertes Wazuh vers
# Elasticsearch/Kibana - preuve par FRAICHEUR (une alerte plus recente
# que le demarrage du test doit apparaitre), jamais par injection
# synthetique.
#
# REECRIT LE 2026-09-24 (incident reel, wef-elk-core) : la version
# precedente (canari "logger" + regle dediee id=100101, elle-meme
# reecrite le 2026-08-31 pour la meme raison) donnait un FAUX NEGATIF -
# confirme en direct : "grep -c WEF_CANARY_TEST alerts.json" = 0, la
# regle 100101 ne s'est jamais declenchee (meme constat deja documente
# dans l'en-tete de WAZ_055_NMAP_SCAN_INTEGRATION.sh, v3 abandonnee, le
# jour meme). Pendant ce temps, wazuh-alerts-4.x-2026.09.24 contenait
# deja 11888 documents reels et le pipeline Logstash "wazuh-alerts"
# tournait sans erreur - le routage convergent fonctionnait en realite,
# seul le mecanisme de test etait casse. Plutot que de reparer une
# troisieme fois un canari synthetique fragile (meme lecon que
# l'abandon des regles custom pour nmap, WAZ_055 v4->v5), ce test
# n'injecte plus rien : il verifie qu'une alerte PLUS RECENTE que son
# propre demarrage apparait - le flux d'evenements FIM/syscheck reel de
# la Forge (verifie tres actif dans les logs : plusieurs evenements par
# seconde) suffit amplement, sans dependre d'une regle custom qui peut
# se re-casser silencieusement.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
source "$PROJECT_ROOT/jobs/lib/es_admin_curl.sh"

TEST_START_ISO="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
echo "[WAZ_037_CONVERGENT_TEST] Recherche d'une alerte plus recente que ${TEST_START_ISO} (preuve de fraicheur, sans injection)..."

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
# BUDGET REMONTE LE 2026-09-09 (incident reel, meme classe de
# contention que WAZ_014/WAZ_020_VERIFY le meme jour) : "systemctl
# restart logstash" (WAZ_035C, juste avant dans la chaine) confirmait
# l'UNITE active bien avant que le PIPELINE lui-meme n'ait fini de
# recharger - preuve reelle dans logstash-plain.log : SIGTERM recu a
# 07:40:28, mais le pipeline "wazuh-alerts" n'a commence a lire
# alerts.json qu'a 07:47:32 (pres de 7 minutes plus tard, sous la
# charge deja bien documentee de cette VM) - largement au-dela des 90s
# alloues ici. Remonte a 480s (8 min) par prudence, marge reelle sur le
# pire cas observe.
WAZ_CONVERGENT_TEST_TIMEOUT_SEC="${WAZ_CONVERGENT_TEST_TIMEOUT_SEC:-480}"
echo "[WAZ_037_CONVERGENT_TEST] Sondage de wazuh-alerts-4.x-* (jusqu'a ${WAZ_CONVERGENT_TEST_TIMEOUT_SEC}s)..."
FOUND=0
QUERY_BODY="{\"query\":{\"range\":{\"@timestamp\":{\"gt\":\"${TEST_START_ISO}\"}}}}"
for i in $(seq 1 $((WAZ_CONVERGENT_TEST_TIMEOUT_SEC / 10))); do
  sleep 10
  COUNT=$(es_admin_curl -X GET "https://127.0.0.1:${ES_PORT}/wazuh-alerts-4.x-*/_count" \
    -H "Content-Type: application/json" -d "$QUERY_BODY" 2>/dev/null \
    | python3 -c "import json,sys
try:
    print(json.load(sys.stdin).get('count', 0))
except Exception:
    print(0)" 2>/dev/null || echo 0)
  if [ "${COUNT:-0}" -gt 0 ] 2>/dev/null; then
    FOUND=1
    echo "[WAZ_037_CONVERGENT_TEST] ${COUNT} alerte(s) plus recente(s) que ${TEST_START_ISO} trouvee(s)."
    break
  fi
done
if [ "$FOUND" -eq 1 ]; then
  echo "[WAZ_037_CONVERGENT_TEST] Mode convergent valide de bout en bout (alertes reelles, aucune injection)."
else
  echo "[WAZ_037_CONVERGENT_TEST] ERREUR : aucune alerte plus recente que ${TEST_START_ISO} apres ${WAZ_CONVERGENT_TEST_TIMEOUT_SEC}s - le routage convergent ne fonctionne pas (ou aucune activite FIM/syscheck reelle sur cette fenetre)." >&2
  exit 1
fi
echo "[WAZ_037_CONVERGENT_TEST] OK."
exit 0
