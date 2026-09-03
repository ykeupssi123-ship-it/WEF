#!/bin/bash
# WAZ_019_FLOOD - WEF_WAZ_RUN_AGENTFLOOD - Deluge massif d'evenements
#
# CORRIGE LE 2026-09-03 (incident reel deploiement MIPREL, voir
# docs/JOURNAL_TECHNIQUE.md) : l'ancienne version injectait via
# "logger -t auth" (20000 appels, un fork de processus par ligne - 11
# minutes reelles pour 20000 lignes). Preuve reelle recueillie en
# diagnostiquant WAZ_020_VERIFY (0 alerte indexee apres le flood) :
#   - /var/log/messages contenait bien les 20000 messages (grep -c confirme)
#   - journalctl -t auth --since/--until n'en contenait AUCUN
#   - /var/ossec/logs/archives/archives.log n'en contenait AUCUN non plus
# Cause reelle : ossec.conf ne surveille que journald (+ audit.log +
# active-responses.log), jamais /var/log/messages directement - et
# journald applique une limite de debit (rate limiting) par defaut qui
# absorbe silencieusement une rafale de 20000 messages quasi-identiques
# en quelques secondes (le canari de WAZ_041_ALERT_CANARY.sh, qui
# n'envoie qu'1 seul message par jour, n'est jamais touche par cette
# limite - d'ou son succes documente alors que celui-ci echouait).
# Corrige : injection directe (bash pur, sans fork) dans un fichier
# dedie, surveille par un <localfile> ajoute ICI (jamais dans le
# ossec.conf de base de WAZ_013 - specifique a ce test), avec sa propre
# regle Wazuh (id 100102, meme principe deja etabli par WAZ_041 pour que
# l'evenement genere une vraie alerte plutot que d'etre seulement
# archive). Resultat mesure : 20000 lignes ecrites en fractions de
# seconde au lieu de 11 minutes.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

FLOOD_LOG="/var/log/wazuh-flood-test.log"
RULES_FILE="/var/ossec/etc/rules/local_rules.xml"
NEED_RESTART=0

echo "[WAZ_019_FLOOD] Preparation du fichier dedie ${FLOOD_LOG}..."
touch "$FLOOD_LOG"
chmod 644 "$FLOOD_LOG"

if ! grep -q "$FLOOD_LOG" /var/ossec/etc/ossec.conf 2>/dev/null; then
  echo "[WAZ_019_FLOOD] Ajout de la surveillance de ${FLOOD_LOG} dans ossec.conf..."
  sed -i "/<\/ossec_config>/i\\
  <localfile>\\
    <log_format>syslog</log_format>\\
    <location>${FLOOD_LOG}</location>\\
  </localfile>" /var/ossec/etc/ossec.conf
  NEED_RESTART=1
else
  echo "[WAZ_019_FLOOD] Surveillance de ${FLOOD_LOG} deja presente dans ossec.conf, ignore."
fi

# Meme principe idempotent/additif que WAZ_041_ALERT_CANARY.sh et
# WAZ_025.sh (corrige le meme jour pour la meme raison) : jamais un
# "cat >" qui ecraserait une regle deja ajoutee par un autre job sur ce
# fichier partage.
mkdir -p "$(dirname "$RULES_FILE")"
if [ ! -f "$RULES_FILE" ]; then
  cat > "$RULES_FILE" << 'RULEEOF'
<group name="factory,local,">
</group>
RULEEOF
fi
if ! grep -q 'id="100102"' "$RULES_FILE" 2>/dev/null; then
  echo "[WAZ_019_FLOOD] Pose de la regle dediee au test de charge (id 100102, niveau 7)..."
  sed -i 's#</group>#  <rule id="100102" level="7">\n    <match>wazuh-test-flood</match>\n    <description>Evenement synthetique du test de charge (WAZ_019_FLOOD) - ignorer, jamais un incident reel.</description>\n    <group>flood_test,</group>\n  </rule>\n</group>#' "$RULES_FILE"
  NEED_RESTART=1
else
  echo "[WAZ_019_FLOOD] Regle 100102 deja presente, ignore."
fi

if [ "$NEED_RESTART" -eq 1 ]; then
  echo "[WAZ_019_FLOOD] Configuration modifiee - redemarrage de wazuh-manager pour l'appliquer..."
  systemctl restart wazuh-manager
  if ! wait_for_service_active wazuh-manager 120 5; then
    echo "[WAZ_019_FLOOD] ERREUR : wazuh-manager n'a pas redemarre proprement apres la mise a jour de la configuration." >&2
    exit 1
  fi
fi

echo "[WAZ_019_FLOOD] Injection de 20000 evenements de test (ecriture directe, sans fork de processus)..."
HOST="$(hostname)"
NOW="$(date '+%b %d %H:%M:%S')"
{
  for i in $(seq 1 20000); do
    printf '%s %s wazuh-test-flood: secure event injection %d\n' "$NOW" "$HOST" "$i"
  done
} >> "$FLOOD_LOG"

echo "[WAZ_019_FLOOD] OK."
exit 0
