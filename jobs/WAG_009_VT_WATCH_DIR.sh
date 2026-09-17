#!/bin/bash
# WAG_009_VT_WATCH_DIR - WEF_WAG_RUN_VTWATCHDIR - Surveillance FIM sur VM2
#
# AJOUTE LE 2026-09-17 (demande explicite : "maintenant si la menace
# vient de VM2 ? illustrons"). Jusqu'ici, tous les tests VirusTotal/IOC
# (WAZ_050/WAZ_051) ont ete faits en deposant des fichiers directement
# sur ELK_HOST (VT_WATCH_DIR surveille par le manager lui-meme, agent
# "wef-elk-core", id 000) - jamais depuis un AGENT_HOST reel.
#
# Ce job ouvre le MEME dossier surveille (VT_WATCH_DIR, vars.conf), mais
# cote AGENT (VM2), dans le propre ossec.conf de l'agent - jamais celui
# du manager. Aucune modification cote ELK_HOST n'est necessaire :
# l'integration VirusTotal de WAZ_050 filtre par rule_id (100100,550,
# 553,554), jamais par agent - un evenement FIM remonte par N'IMPORTE
# QUEL agent declenche la meme regle, donc la meme soumission VT,
# automatiquement. Preuve attendue : l'alerte generee portera le nom de
# CET agent (AGENT_NAME, vars.conf) au lieu de "wef-elk-core".
#
# ossec.conf d'un AGENT_HOST n'est PAS verrouille par chattr (WAZ_032
# est un job ELK_HOST uniquement, jamais applique ici) - pas de
# deverrouillage/reverrouillage necessaire, contrairement a WAZ_050/051/052.
set -uo pipefail
source "$VARS_FILE"

WATCH_DIR="${VT_WATCH_DIR:-/root/wef_vt_watch}"
echo "[WAG_009_VT_WATCH_DIR] Preparation du dossier surveille ${WATCH_DIR} sur cet agent..."
mkdir -p "$WATCH_DIR"
chmod 700 "$WATCH_DIR"

OSSEC_CONF="/var/ossec/etc/ossec.conf"
[ -f "$OSSEC_CONF" ] || { echo "[WAG_009_VT_WATCH_DIR] ERREUR : ${OSSEC_CONF} introuvable (WAG_003/WAG_004 doivent avoir tourne)." >&2; exit 1; }

MARKER="<!-- WEF_AGENT_VT_WATCH_CONFIG (WAG_009, genere automatiquement - ne pas editer a la main) -->"
if grep -qF "$MARKER" "$OSSEC_CONF"; then
  echo "[WAG_009_VT_WATCH_DIR] Bloc deja pose, retrait avant reecriture (evite les doublons a chaque rejeu)..."
  sed -i "\|^${MARKER//\//\\/}\$|,\|^<!-- WEF_AGENT_VT_WATCH_CONFIG_END -->\$|d" "$OSSEC_CONF"
fi

echo "[WAG_009_VT_WATCH_DIR] Ajout de la surveillance FIM temps reel de ${WATCH_DIR}..."
{
  echo "$MARKER"
  echo "<ossec_config>"
  echo "  <syscheck>"
  echo "    <directories realtime=\"yes\" report_changes=\"yes\">${WATCH_DIR}</directories>"
  echo "  </syscheck>"
  echo "</ossec_config>"
  echo "<!-- WEF_AGENT_VT_WATCH_CONFIG_END -->"
} >> "$OSSEC_CONF"
grep -qF "$MARKER" "$OSSEC_CONF" || { echo "[WAG_009_VT_WATCH_DIR] ERREUR : bloc absent apres ecriture." >&2; exit 1; }

echo "[WAG_009_VT_WATCH_DIR] Redemarrage de wazuh-agent pour appliquer..."
systemctl restart wazuh-agent

for i in $(seq 1 30); do
  systemctl is-active --quiet wazuh-agent && { echo "[WAG_009_VT_WATCH_DIR] wazuh-agent actif."; echo "[WAG_009_VT_WATCH_DIR] OK. Deposez un fichier dans ${WATCH_DIR} sur CETTE machine (VM2) pour simuler une menace venant de VM2."; exit 0; }
  sleep 2
done

echo "[WAG_009_VT_WATCH_DIR] ERREUR : wazuh-agent n'a pas redemarre correctement." >&2
journalctl -u wazuh-agent -n 30 --no-pager 2>/dev/null || true
exit 1
