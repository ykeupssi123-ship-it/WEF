#!/bin/bash
# WAZ_041_ALERT_CANARY - WEF_WAZ_RUN_ALERTCANARY - Test d'alerte
# synthetique quotidien (preuve de vie de bout en bout du pipeline)
#
# AJOUTE LE 2026-08-31 (point #9 de la mission, "tests d'alerte" cite
# nommement par l'utilisateur). Reutilise EXACTEMENT la technique deja
# eprouvee par WAZ_037_CONVERGENT_TEST.sh (logger -> recherche dans
# l'index) plutot que d'inventer une nouvelle methode - seule
# difference : celui-ci tourne en PERMANENCE (timer quotidien, jamais
# un test de construction ponctuel) et interroge wazuh-indexer (la
# cible reelle en mode Souverain, l'etat de repos par defaut de cette
# usine - voir WAZ_035/WAZ_039), pas Elasticsearch classique.
#
# BUT REEL : detecter une casse SILENCIEUSE du pipeline (ex. le meme
# bug ssl_client_authentication trouve aujourd'hui, qui a laisse le
# pipeline principal de Logstash mort depuis 08h du matin SANS
# qu'aucune alerte ne le signale) avant qu'un humain ne s'en apercoive
# par hasard. Le tag "WEF_CANARY_TEST" (jamais un texte ambigu) permet a
# quiconque de reconnaitre immediatement un evenement synthetique dans
# le Dashboard/Kibana - jamais confondu avec un incident reel.
#
# Ce job installe le timer (BUILD, une fois) ; le timer lui-meme est le
# job RUN qui tourne en permanence ensuite (meme distinction que
# INFRA_004_HEALTH_GUARDIAN.sh).
#
# CORRIGE LE 2026-08-31 (meme jour, PREMIER declenchement reel de ce
# canari - jamais suppose fonctionner, verifie) : un simple
# "logger -t wazuh-canary-test ..." ne genere PAS d'alerte persistee -
# confirme en reel : le message n'apparait meme pas dans
# /var/ossec/logs/alerts/alerts.json (recherche exhaustive de l'id du
# canari, aucune occurrence). Cause reelle : `<log_alert_level>3</
# log_alert_level>` (confirme dans ossec.conf) - un syslog generique ne
# correspond a aucune regle Wazuh de niveau >= 3 (au mieux une regle
# fourre-tout de tres bas niveau, jamais ecrite sur disque). Corrige :
# ce job pose sa PROPRE regle personnalisee dediee (id 100101, niveau
# 3, correspondance directe sur le tag WEF_CANARY_TEST) - garantit une
# alerte reellement persistee a chaque declenchement, plutot que de
# dependre d'un comportement de regle par defaut non garanti. Ajoutee
# au meme fichier que WAZ_025.sh (local_rules.xml), jamais en doublon
# (idempotent).
#
# CORRIGE ENCORE LE 2026-08-31 (meme jour, en construisant la bascule
# Convergent/Souverain reelle - WAZ_035/WAZ_039) : ce canari interrogeait
# EN DUR wazuh-indexer, quelle que soit la destination REELLE des
# alertes a l'instant du test - un faux-positif systematique et
# quotidien des qu'un operateur bascule vers le mode convergent
# (Kibana), puisque plus aucune alerte n'atterrit alors dans
# wazuh-indexer, sans que ce soit une panne. Corrige : le script genere
# lit desormais ${STATE_DIR}/WAZ_ALERTS_ROUTE.state (ecrit par WAZ_035/
# WAZ_039, "INDEXER" par defaut si absent) et interroge le BON backend
# (wazuh-indexer ou Elasticsearch classique) avec les identifiants
# correspondants - jamais un backend suppose fixe.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

CHECK_SCRIPT="/usr/local/sbin/wef-alert-canary.sh"
SERVICE_FILE="/etc/systemd/system/wef-alert-canary.service"
TIMER_FILE="/etc/systemd/system/wef-alert-canary.timer"
RULES_FILE="/var/ossec/etc/rules/local_rules.xml"

WAZUH_INDEXER_ADMIN_PW="$(read_or_generate_secret "$WAZ_INDEXER_ADMIN_PASSWORD_FILE" non)" || exit 1

if ! grep -q 'id="100101"' "$RULES_FILE" 2>/dev/null; then
  echo "[WAZ_041] Pose de la regle dediee au canari (id 100101, niveau 3)..."
  # Insere juste avant </group> final (meme structure que WAZ_025.sh :
  # un seul <group> englobant dans ce fichier) - jamais un deuxieme
  # <group> racine, pour rester lisible et coherent avec l'existant.
  sed -i 's#</group>#  <rule id="100101" level="3">\n    <match>WEF_CANARY_TEST</match>\n    <description>Test d'"'"'alerte synthetique quotidien de l'"'"'usine (WAZ_041_ALERT_CANARY) - ignorer, jamais un incident reel.</description>\n    <group>canary,</group>\n  </rule>\n</group>#' "$RULES_FILE"
  systemctl restart wazuh-manager 2>/dev/null || true
  if ! wait_for_service_active wazuh-manager 120 5; then
    echo "[WAZ_041] ERREUR : wazuh-manager n'a pas redemarre proprement apres la pose de la regle du canari." >&2
    exit 1
  fi
else
  echo "[WAZ_041] Regle du canari deja presente, ignore."
fi

echo "[WAZ_041] Installation du script de canari ${CHECK_SCRIPT}..."
cat > "$CHECK_SCRIPT" << SCRIPTEOF
#!/bin/bash
# Canari d'alerte quotidien - genere par jobs/WAZ_041_ALERT_CANARY.sh.
# Injecte un evenement tagge, verifie sa presence reelle dans
# l'indexeur apres un delai raisonnable, journalise le verdict (succes
# ET echec - contrairement aux gardes INFRA_00x, une preuve de vie
# reguliere est une information utile en soi, pas seulement les ecarts).
ROUTE="\$(cat "${STATE_DIR}/WAZ_ALERTS_ROUTE.state" 2>/dev/null || echo INDEXER)"
if [ "\$ROUTE" = "ELASTICSEARCH" ]; then
  BACKEND_NOM="Elasticsearch (mode convergent)"
  BACKEND_URL="https://127.0.0.1:${ES_PORT}"
  BACKEND_USER="elastic"
  BACKEND_PW="\$(cat "${STATE_DIR}/es_bootstrap_password.secret" 2>/dev/null)"
else
  BACKEND_NOM="wazuh-indexer (mode souverain)"
  BACKEND_URL="https://127.0.0.1:${WAZ_INDEXER_PORT:-9200}"
  BACKEND_USER="${WAZ_INDEXER_ADMIN_USER}"
  BACKEND_PW="\$(cat "${WAZ_INDEXER_ADMIN_PASSWORD_FILE}" 2>/dev/null)"
fi
CANARY_ID="\$(date +%s)-\$\$"
logger -t wazuh-canary-test "WEF_CANARY_TEST id=\${CANARY_ID} - test automatique quotidien, ignorer"
sleep 30
RESULT=\$(curl -sk -u "\${BACKEND_USER}:\${BACKEND_PW}" \\
  "\${BACKEND_URL}/wazuh-alerts-4.x-*/_search?q=WEF_CANARY_TEST+AND+\${CANARY_ID}" 2>/dev/null)
if echo "\$RESULT" | grep -q "\${CANARY_ID}"; then
  logger -t wef-alert-canary "OK : canari id=\${CANARY_ID} retrouve dans \${BACKEND_NOM} - pipeline d'alertes fonctionnel de bout en bout."
else
  logger -t wef-alert-canary "ALERTE : canari id=\${CANARY_ID} INTROUVABLE dans \${BACKEND_NOM} apres 30s - pipeline d'alertes possiblement casse (verifier logstash/wazuh-manager)."
fi
SCRIPTEOF
chmod 750 "$CHECK_SCRIPT"
chown root:root "$CHECK_SCRIPT"

echo "[WAZ_041] Installation du service/timer systemd (quotidien)..."
cat > "$SERVICE_FILE" << 'UNITEOF'
[Unit]
Description=Test d'alerte synthetique quotidien (WAZ_041_ALERT_CANARY)

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/wef-alert-canary.sh
UNITEOF

cat > "$TIMER_FILE" << 'TIMEREOF'
[Unit]
Description=Declenche le canari d'alerte une fois par jour

[Timer]
OnCalendar=*-*-* 06:00:00
RandomizedDelaySec=300
Persistent=true

[Install]
WantedBy=timers.target
TIMEREOF

systemctl daemon-reload
systemctl enable --now wef-alert-canary.timer

if ! systemctl is-active wef-alert-canary.timer >/dev/null 2>&1; then
  echo "[WAZ_041] ERREUR : wef-alert-canary.timer n'est pas actif apres activation." >&2
  systemctl status wef-alert-canary.timer --no-pager >&2 || true
  exit 1
fi

echo "[WAZ_041] OK (wef-alert-canary.timer actif, test quotidien a 06h - voir journalctl -t wef-alert-canary)."
exit 0
