#!/bin/bash
# WAZ_051_IOC_CDB_LIST - WEF_WAZ_RUN_IOCCDBLIST
#
# AJOUTE LE 2026-09-16 (playbook PB-008, demande explicite : "un job RUN
# pour le Threat Intelligence / IOC matching"). Sans plateforme externe
# (pas de serveur MISP dans ce projet) : une liste CDB Wazuh locale de
# hashes MD5 connus comme malveillants (IOC_MD5_BLOCKLIST, vars.conf,
# meme principe de liste configurable que SKIP_JOBS/ES_DEMO_INDEX_PREFIXES),
# correlee a CHAQUE evenement FIM (syscheck) via une regle dediee. Un
# fichier dont le hash correspond a la liste declenche une alerte
# "IOC connu detecte", independamment de VirusTotal (WAZ_050) - les
# deux peuvent tourner ensemble ou separement.
#
# CORRIGE LE 2026-09-16 (par anticipation, meme cause reelle diagnostiquee
# et corrigee sur WAZ_050 le meme soir - voir ce fichier pour le detail
# complet) : la regle 100200 chaine sur <if_sid>100100,550,553,554</if_sid>,
# jamais sur <if_group>syscheck</if_group>, qui ne se declenche jamais
# dans cet environnement (regle preexistante WAZ_025/100100 capte
# l'evenement en premier, sans exposer le groupe syscheck).
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

BLOCKLIST_FILE="/var/ossec/etc/lists/blacklist-md5"
echo "[WAZ_051_IOC_CDB_LIST] Generation de la liste CDB (${BLOCKLIST_FILE})..."
mkdir -p "$(dirname "$BLOCKLIST_FILE")"
: > "$BLOCKLIST_FILE"
IFS=',' read -ra IOC_ENTRIES <<< "${IOC_MD5_BLOCKLIST:-}"
COUNT=0
for entry in "${IOC_ENTRIES[@]}"; do
  entry="$(echo "$entry" | xargs)"
  [ -z "$entry" ] && continue
  echo "$entry" >> "$BLOCKLIST_FILE"
  COUNT=$((COUNT+1))
done
chmod 640 "$BLOCKLIST_FILE"
echo "[WAZ_051_IOC_CDB_LIST] ${COUNT} entree(s) IOC ecrite(s)."
if [ "$COUNT" -eq 0 ]; then
  echo "[WAZ_051_IOC_CDB_LIST] ERREUR : IOC_MD5_BLOCKLIST est vide dans vars.conf - rien a correler." >&2
  exit 1
fi

OSSEC_CONF="/var/ossec/etc/ossec.conf"
[ -f "$OSSEC_CONF" ] || { echo "[WAZ_051_IOC_CDB_LIST] ERREUR : ${OSSEC_CONF} introuvable." >&2; exit 1; }

# CORRIGE LE 2026-09-16 (incident reel, wef-elk-core : "Operation non
# permise" sur ossec.conf) : deja verrouille immuable par WAZ_032
# (chattr +i) - meme motif deja etabli ailleurs dans ce projet
# (WAZ_014E_INDEXER_CONNECTOR.sh/WAZ_019_FLOOD.sh).
if lsattr "$OSSEC_CONF" 2>/dev/null | grep -q '^....i'; then
  echo "[WAZ_051_IOC_CDB_LIST] ${OSSEC_CONF} est immuable (deja verrouille par WAZ_032) - deverrouillage temporaire avant reecriture."
  chattr -i "$OSSEC_CONF"
fi

MARKER="<!-- WEF_IOC_LIST_CONFIG (WAZ_051, genere automatiquement - ne pas editer a la main) -->"
if grep -qF "$MARKER" "$OSSEC_CONF"; then
  echo "[WAZ_051_IOC_CDB_LIST] Bloc deja pose dans ossec.conf, retrait avant reecriture..."
  sed -i "\|^${MARKER//\//\\/}\$|,\|^<!-- WEF_IOC_LIST_CONFIG_END -->\$|d" "$OSSEC_CONF"
fi
echo "[WAZ_051_IOC_CDB_LIST] Declaration de la liste CDB dans ossec.conf..."
{
  echo "$MARKER"
  echo "<ossec_config>"
  echo "  <ruleset>"
  echo "    <list>etc/lists/blacklist-md5</list>"
  echo "  </ruleset>"
  echo "</ossec_config>"
  echo "<!-- WEF_IOC_LIST_CONFIG_END -->"
} >> "$OSSEC_CONF"
grep -qF "$MARKER" "$OSSEC_CONF" || { echo "[WAZ_051_IOC_CDB_LIST] ERREUR : bloc absent apres ecriture dans ossec.conf (fichier verrouille ? voir chattr/lsattr)." >&2; exit 1; }

echo "[WAZ_051_IOC_CDB_LIST] Reverrouillage de ${OSSEC_CONF} (droits + chattr +i)..."
chown root:wazuh "$OSSEC_CONF"
chmod 640 "$OSSEC_CONF"
chattr +i "$OSSEC_CONF"

RULES_FILE="/var/ossec/etc/rules/local_rules.xml"
[ -f "$RULES_FILE" ] || { echo "[WAZ_051_IOC_CDB_LIST] ERREUR : ${RULES_FILE} introuvable (deja inclus par defaut dans ossec.conf vendor)." >&2; exit 1; }
MARKER_RULE="<!-- WEF_IOC_RULE (WAZ_051, genere automatiquement - ne pas editer a la main) -->"
if grep -qF "$MARKER_RULE" "$RULES_FILE"; then
  echo "[WAZ_051_IOC_CDB_LIST] Regle IOC deja posee, retrait avant reecriture..."
  sed -i "\|^${MARKER_RULE//\//\\/}\$|,\|^<!-- WEF_IOC_RULE_END -->\$|d" "$RULES_FILE"
fi
# CORRIGE LE 2026-09-16 (meme cause reelle que WAZ_050, trouvee et
# confirmee sur wef-elk-core : la regle preexistante WAZ_025/id 100100
# ("Modification detectee sur un fichier surveille de la Forge") capte
# TOUT evenement FIM en premier et n'expose que ses propres groupes
# (local,syslog,sshd), jamais "syscheck" - un <if_group>syscheck</if_group>
# ici ne se declencherait donc jamais, silencieusement, exactement comme
# WAZ_050 avant son correctif. Chaine directement sur la regle 100100
# elle-meme (celle qui se declenche reellement) via <if_sid>, plus les
# regles FIM standard (550/553/554) pour rester correct sur un futur
# environnement qui n'aurait pas cette regle 100100.
echo "[WAZ_051_IOC_CDB_LIST] Ajout de la regle de correlation IOC (id 100200)..."
{
  echo "$MARKER_RULE"
  echo "<group name=\"syscheck,ioc,\">"
  echo "  <rule id=\"100200\" level=\"12\">"
  echo "    <if_sid>100100,550,553,554</if_sid>"
  echo "    <list field=\"md5\" lookup=\"match_key\">etc/lists/blacklist-md5</list>"
  echo "    <description>IOC connu detecte : fichier correspondant a un hash MD5 de la liste de menace WEF</description>"
  echo "    <group>ioc_match,</group>"
  echo "  </rule>"
  echo "</group>"
  echo "<!-- WEF_IOC_RULE_END -->"
} >> "$RULES_FILE"
grep -qF "$MARKER_RULE" "$RULES_FILE" || { echo "[WAZ_051_IOC_CDB_LIST] ERREUR : regle IOC absente apres ecriture dans ${RULES_FILE}." >&2; exit 1; }

echo "[WAZ_051_IOC_CDB_LIST] Redemarrage de wazuh-manager pour appliquer..."
systemctl restart wazuh-manager
if ! wait_for_service_active wazuh-manager 180 5; then
  echo "[WAZ_051_IOC_CDB_LIST] ERREUR : wazuh-manager n'a pas redemarre." >&2
  journalctl -u wazuh-manager -n 30 --no-pager 2>/dev/null || true
  exit 1
fi

echo "[WAZ_051_IOC_CDB_LIST] OK. Un fichier dont le hash MD5 figure dans la liste declenche desormais la regle 100200."
exit 0
