#!/bin/bash
# WAG_008_AUDITD_INTEGRATION - WEF_WAG_RUN_AUDITD - Audit des commandes systeme
#
# AJOUTE LE 2026-09-16 (playbook PB-006, demande explicite : "un job RUN
# pour l'audit des commandes systeme (auditd, Linux)"). Installe et
# active auditd (traçabilite de qui execute quoi, notamment via sudo -
# usage standard pour la conformite), ajoute une regle d'audit sur les
# executions de commandes (execve), puis fait lire le journal d'audit
# par l'agent Wazuh - visible dans le Dashboard comme n'importe quelle
# autre source de log.
set -uo pipefail
source "$VARS_FILE"

install_if_missing(){
  local pkg="$1"
  if rpm -q "$pkg" &>/dev/null; then
    echo "[WAG_008_AUDITD_INTEGRATION] ${pkg} deja installe, ignore."
    return 0
  fi
  echo "[WAG_008_AUDITD_INTEGRATION] Installation de ${pkg}..."
  if ! dnf install -y "$pkg"; then
    echo "[WAG_008_AUDITD_INTEGRATION] AVERTISSEMENT : dnf install ${pkg} a echoue, nouvel essai en forcant l'IPv4..."
    dnf install -y --setopt=ip_resolve=4 "$pkg" || { echo "[WAG_008_AUDITD_INTEGRATION] ERREUR : dnf install ${pkg} a echoue meme en IPv4 force." >&2; return 1; }
  fi
  rpm -q "$pkg" &>/dev/null || { echo "[WAG_008_AUDITD_INTEGRATION] ERREUR : ${pkg} toujours absent apres dnf install." >&2; return 1; }
}
install_if_missing audit || exit 1

echo "[WAG_008_AUDITD_INTEGRATION] Activation et demarrage de auditd..."
systemctl enable auditd
systemctl restart auditd
for i in $(seq 1 30); do
  systemctl is-active --quiet auditd && break
  sleep 2
done
systemctl is-active --quiet auditd || { echo "[WAG_008_AUDITD_INTEGRATION] ERREUR : auditd n'a pas demarre." >&2; exit 1; }

RULE_FILE="/etc/audit/rules.d/wef-command-audit.rules"
RULE_LINE="-a always,exit -F arch=b64 -S execve -k wef_commands"
if [ -f "$RULE_FILE" ] && grep -qF "$RULE_LINE" "$RULE_FILE"; then
  echo "[WAG_008_AUDITD_INTEGRATION] Regle d'audit deja presente, ignore."
else
  echo "[WAG_008_AUDITD_INTEGRATION] Ajout de la regle d'audit des executions de commandes..."
  echo "$RULE_LINE" > "$RULE_FILE"
  chmod 640 "$RULE_FILE"
  if command -v augenrules >/dev/null 2>&1; then
    augenrules --load
  else
    auditctl -R "$RULE_FILE"
  fi
fi

OSSEC_CONF="/var/ossec/etc/ossec.conf"
[ -f "$OSSEC_CONF" ] || { echo "[WAG_008_AUDITD_INTEGRATION] ERREUR : ${OSSEC_CONF} introuvable (WAG_003/WAG_004 doivent avoir tourne)." >&2; exit 1; }
MARKER="<!-- WEF_AUDITD_CONFIG (WAG_008, genere automatiquement - ne pas editer a la main) -->"
if grep -qF "$MARKER" "$OSSEC_CONF"; then
  echo "[WAG_008_AUDITD_INTEGRATION] Bloc deja pose dans ossec.conf, retrait avant reecriture..."
  sed -i "\|^${MARKER//\//\\/}\$|,\|^<!-- WEF_AUDITD_CONFIG_END -->\$|d" "$OSSEC_CONF"
fi
echo "[WAG_008_AUDITD_INTEGRATION] Ajout de la lecture de /var/log/audit/audit.log par l'agent..."
{
  echo "$MARKER"
  echo "<ossec_config>"
  echo "  <localfile>"
  echo "    <log_format>audit</log_format>"
  echo "    <location>/var/log/audit/audit.log</location>"
  echo "  </localfile>"
  echo "</ossec_config>"
  echo "<!-- WEF_AUDITD_CONFIG_END -->"
} >> "$OSSEC_CONF"

echo "[WAG_008_AUDITD_INTEGRATION] Redemarrage de wazuh-agent pour appliquer..."
systemctl restart wazuh-agent
for i in $(seq 1 30); do
  systemctl is-active --quiet wazuh-agent && { echo "[WAG_008_AUDITD_INTEGRATION] wazuh-agent actif."; echo "[WAG_008_AUDITD_INTEGRATION] OK."; exit 0; }
  sleep 2
done

echo "[WAG_008_AUDITD_INTEGRATION] ERREUR : wazuh-agent n'a pas redemarre correctement." >&2
journalctl -u wazuh-agent -n 30 --no-pager 2>/dev/null || true
exit 1
