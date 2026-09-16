#!/bin/bash
# WAG_007_ROOTCHECK - WEF_WAG_RUN_ROOTCHECK - Detection de rootkits/malwares
#
# AJOUTE LE 2026-09-16 (playbook PB-005, demande explicite : "un job RUN
# pour la detection de rootkit/malware, module Rootcheck"). Le paquet
# wazuh-agent livre deja un bloc <rootcheck> par defaut (frequence
# 43200s = 12h, trop lent pour une demo) - ce job ne le desactive JAMAIS,
# il en garantit l'activation explicite et resserre uniquement la
# frequence (WAZ_ROOTCHECK_FREQUENCY_SEC, vars.conf).
#
# Idempotent par marqueur (meme discipline que INFRA_007_NTP_SERVER.sh) :
# un bloc <ossec_config> autonome, jamais imbrique dans un bloc
# existant - Wazuh accepte plusieurs blocs <ossec_config> distincts
# dans le meme fichier, chacun analyse independamment.
set -uo pipefail
source "$VARS_FILE"

OSSEC_CONF="/var/ossec/etc/ossec.conf"
[ -f "$OSSEC_CONF" ] || { echo "[WAG_007_ROOTCHECK] ERREUR : ${OSSEC_CONF} introuvable (WAG_003/WAG_004 doivent avoir tourne)." >&2; exit 1; }

FREQ="${WAZ_ROOTCHECK_FREQUENCY_SEC:-300}"
MARKER="<!-- WEF_ROOTCHECK_CONFIG (WAG_007, genere automatiquement - ne pas editer a la main) -->"

if grep -qF "$MARKER" "$OSSEC_CONF"; then
  echo "[WAG_007_ROOTCHECK] Bloc deja pose, retrait avant reecriture (evite les doublons a chaque rejeu)..."
  sed -i "\|^${MARKER//\//\\/}\$|,\|^<!-- WEF_ROOTCHECK_CONFIG_END -->\$|d" "$OSSEC_CONF"
fi

echo "[WAG_007_ROOTCHECK] Activation du module Rootcheck (frequence ${FREQ}s)..."
{
  echo "$MARKER"
  echo "<ossec_config>"
  echo "  <rootcheck>"
  echo "    <disabled>no</disabled>"
  echo "    <check_unixaudit>yes</check_unixaudit>"
  echo "    <check_files>yes</check_files>"
  echo "    <check_trojans>yes</check_trojans>"
  echo "    <check_dev>yes</check_dev>"
  echo "    <check_sys>yes</check_sys>"
  echo "    <check_pids>yes</check_pids>"
  echo "    <check_ports>yes</check_ports>"
  echo "    <check_if>yes</check_if>"
  echo "    <frequency>${FREQ}</frequency>"
  echo "    <rootkit_files>etc/shared/rootkit_files.txt</rootkit_files>"
  echo "    <rootkit_trojans>etc/shared/rootkit_trojans.txt</rootkit_trojans>"
  echo "    <skip_nfs>yes</skip_nfs>"
  echo "  </rootcheck>"
  echo "</ossec_config>"
  echo "<!-- WEF_ROOTCHECK_CONFIG_END -->"
} >> "$OSSEC_CONF"

echo "[WAG_007_ROOTCHECK] Redemarrage de wazuh-agent pour appliquer..."
systemctl restart wazuh-agent

for i in $(seq 1 30); do
  systemctl is-active --quiet wazuh-agent && { echo "[WAG_007_ROOTCHECK] wazuh-agent actif."; echo "[WAG_007_ROOTCHECK] OK."; exit 0; }
  sleep 2
done

echo "[WAG_007_ROOTCHECK] ERREUR : wazuh-agent n'a pas redemarre correctement." >&2
journalctl -u wazuh-agent -n 30 --no-pager 2>/dev/null || true
exit 1
