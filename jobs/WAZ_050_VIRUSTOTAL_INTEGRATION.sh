#!/bin/bash
# WAZ_050_VIRUSTOTAL_INTEGRATION - WEF_WAZ_RUN_VTINTEGR
#
# AJOUTE LE 2026-09-16 (playbook PB-007, demande explicite : "un job RUN
# pour l'integration VirusTotal"). Chaque fichier detecte par le FIM
# (syscheck) dans VT_WATCH_DIR est automatiquement soumis a l'API
# VirusTotal par le manager - si son hash est deja connu comme
# malveillant, une alerte est generee. Necessite une cle API VirusTotal
# GRATUITE, creee par l'operateur lui-meme sur virustotal.com - jamais
# generee ni devinee ici (voir vars.conf, VIRUSTOTAL_API_KEY_FILE, meme
# principe que SMTP_PASS_FILE).
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

if [ ! -s "${VIRUSTOTAL_API_KEY_FILE:-}" ]; then
  echo "[WAZ_050_VIRUSTOTAL_INTEGRATION] ERREUR : ${VIRUSTOTAL_API_KEY_FILE} absent ou vide." >&2
  echo "Creez une cle API gratuite sur https://www.virustotal.com puis :" >&2
  echo "  echo -n 'votre_cle_api' > ${VIRUSTOTAL_API_KEY_FILE}" >&2
  echo "  chmod 600 ${VIRUSTOTAL_API_KEY_FILE}" >&2
  exit 1
fi
VT_API_KEY="$(cat "$VIRUSTOTAL_API_KEY_FILE")"

WATCH_DIR="${VT_WATCH_DIR:-/root/wef_vt_watch}"
echo "[WAZ_050_VIRUSTOTAL_INTEGRATION] Preparation du dossier surveille ${WATCH_DIR}..."
mkdir -p "$WATCH_DIR"
chmod 700 "$WATCH_DIR"

OSSEC_CONF="/var/ossec/etc/ossec.conf"
[ -f "$OSSEC_CONF" ] || { echo "[WAZ_050_VIRUSTOTAL_INTEGRATION] ERREUR : ${OSSEC_CONF} introuvable." >&2; exit 1; }

# CORRIGE LE 2026-09-16 (incident reel, wef-elk-core : "Operation non
# permise" sur ossec.conf) : deja verrouille immuable par WAZ_032
# (chattr +i) - meme motif deja etabli ailleurs dans ce projet
# (WAZ_014E_INDEXER_CONNECTOR.sh/WAZ_019_FLOOD.sh) : deverrouiller
# temporairement, reecrire, puis TOUJOURS reverrouiller (droits root:wazuh
# 640 restaures avant le chattr +i final, jamais suppose deja corrects).
if lsattr "$OSSEC_CONF" 2>/dev/null | grep -q '^....i'; then
  echo "[WAZ_050_VIRUSTOTAL_INTEGRATION] ${OSSEC_CONF} est immuable (deja verrouille par WAZ_032) - deverrouillage temporaire avant reecriture."
  chattr -i "$OSSEC_CONF"
fi

MARKER_FIM="<!-- WEF_VT_FIM_CONFIG (WAZ_050, genere automatiquement - ne pas editer a la main) -->"
if grep -qF "$MARKER_FIM" "$OSSEC_CONF"; then
  echo "[WAZ_050_VIRUSTOTAL_INTEGRATION] Bloc FIM deja pose, retrait avant reecriture..."
  sed -i "\|^${MARKER_FIM//\//\\/}\$|,\|^<!-- WEF_VT_FIM_CONFIG_END -->\$|d" "$OSSEC_CONF"
fi
echo "[WAZ_050_VIRUSTOTAL_INTEGRATION] Ajout de la surveillance FIM temps reel de ${WATCH_DIR}..."
{
  echo "$MARKER_FIM"
  echo "<ossec_config>"
  echo "  <syscheck>"
  echo "    <directories realtime=\"yes\" report_changes=\"yes\">${WATCH_DIR}</directories>"
  echo "  </syscheck>"
  echo "</ossec_config>"
  echo "<!-- WEF_VT_FIM_CONFIG_END -->"
} >> "$OSSEC_CONF"
grep -qF "$MARKER_FIM" "$OSSEC_CONF" || { echo "[WAZ_050_VIRUSTOTAL_INTEGRATION] ERREUR : bloc FIM absent apres ecriture (fichier verrouille ? voir chattr/lsattr)." >&2; exit 1; }

# Jamais le contenu de la cle API n'est ecrit dans un echo/log - seul le
# bloc XML genere ci-dessous la contient, dans ossec.conf lui-meme
# (proprietaire root, meme sensibilite qu'un mot de passe deja gere
# ailleurs dans ce fichier par le paquet Wazuh).
MARKER_VT="<!-- WEF_VT_INTEGRATION_CONFIG (WAZ_050, genere automatiquement - ne pas editer a la main) -->"
if grep -qF "$MARKER_VT" "$OSSEC_CONF"; then
  echo "[WAZ_050_VIRUSTOTAL_INTEGRATION] Bloc integration deja pose, retrait avant reecriture..."
  sed -i "\|^${MARKER_VT//\//\\/}\$|,\|^<!-- WEF_VT_INTEGRATION_CONFIG_END -->\$|d" "$OSSEC_CONF"
fi
echo "[WAZ_050_VIRUSTOTAL_INTEGRATION] Ajout de l'integration VirusTotal (groupe syscheck)..."
{
  echo "$MARKER_VT"
  echo "<ossec_config>"
  echo "  <integration>"
  echo "    <name>virustotal</name>"
  echo "    <api_key>${VT_API_KEY}</api_key>"
  echo "    <group>syscheck</group>"
  echo "    <alert_format>json</alert_format>"
  echo "  </integration>"
  echo "</ossec_config>"
  echo "<!-- WEF_VT_INTEGRATION_CONFIG_END -->"
} >> "$OSSEC_CONF"
grep -qF "$MARKER_VT" "$OSSEC_CONF" || { echo "[WAZ_050_VIRUSTOTAL_INTEGRATION] ERREUR : bloc integration absent apres ecriture (fichier verrouille ? voir chattr/lsattr)." >&2; exit 1; }

echo "[WAZ_050_VIRUSTOTAL_INTEGRATION] Reverrouillage de ${OSSEC_CONF} (droits + chattr +i)..."
chown root:wazuh "$OSSEC_CONF"
chmod 640 "$OSSEC_CONF"
chattr +i "$OSSEC_CONF"

echo "[WAZ_050_VIRUSTOTAL_INTEGRATION] Redemarrage de wazuh-manager pour appliquer..."
systemctl restart wazuh-manager
if ! wait_for_service_active wazuh-manager 180 5; then
  echo "[WAZ_050_VIRUSTOTAL_INTEGRATION] ERREUR : wazuh-manager n'a pas redemarre." >&2
  journalctl -u wazuh-manager -n 30 --no-pager 2>/dev/null || true
  exit 1
fi

echo "[WAZ_050_VIRUSTOTAL_INTEGRATION] OK. Deposez un fichier dans ${WATCH_DIR} pour declencher une soumission a VirusTotal."
exit 0
