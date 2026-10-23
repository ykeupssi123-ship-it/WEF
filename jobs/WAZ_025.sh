#!/bin/bash
# WAZ_025 - WEF_WAZ_BLD_RULEADDCUSTOM - Regles de detection specifiques
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
echo "[WAZ_025] Injection des regles personnalisees..."

# CORRIGE LE 2026-10-05 (bug reel trouve en rejouant la cascade FONC-08
# avant la demo : WAZ_040_KIBANA_SILENT echouait car sa regle canari
# n'apparaissait jamais dans les vraies alertes - en remontant la cause,
# /var/ossec/etc/rules/local_rules.xml n'est PAS charge par analysisd sur
# cette installation (deja confirme le 2026-09-30, voir le commentaire
# laisse dans ce fichier). La regle 100100 ecrite ici n'a donc jamais
# declenche une seule fois en conditions reelles (verifie : 0 occurrence
# dans alerts.json). Redirige vers le MEME fichier reellement charge que
# WAZ_060/WAZ_061 (ruleset/rules/9950-wef_custom_rules.xml), avec le
# meme motif marqueur/bloc deja etabli et deja prouve fonctionner ce
# soir (regles 100210-100220 bien presentes dans de vraies alertes).
RULES_FILE="/var/ossec/ruleset/rules/9950-wef_custom_rules.xml"
mkdir -p "$(dirname "$RULES_FILE")"
[ -f "$RULES_FILE" ] || : > "$RULES_FILE"

MARKER_RULE="<!-- WEF_FIM_RULE (WAZ_025, genere automatiquement - ne pas editer a la main) -->"
if grep -qF "$MARKER_RULE" "$RULES_FILE"; then
  echo "[WAZ_025] Regle 100100 deja posee, retrait avant reecriture..."
  sed -i "\|^${MARKER_RULE//\//\/}\$|,\|^<!-- WEF_FIM_RULE_END -->\$|d" "$RULES_FILE"
fi
{
  echo "$MARKER_RULE"
  echo '<group name="factory,local,">'
  echo '  <rule id="100100" level="7">'
  echo '    <if_group>syscheck</if_group>'
  echo '    <description>Modification detectee sur un fichier surveille de la Forge</description>'
  echo '  </rule>'
  echo '</group>'
  echo "<!-- WEF_FIM_RULE_END -->"
} >> "$RULES_FILE"
grep -qF "$MARKER_RULE" "$RULES_FILE" || { echo "[WAZ_025] ERREUR : regle 100100 absente apres ecriture dans ${RULES_FILE}." >&2; exit 1; }

echo "[WAZ_025] Reverrouillage de ${RULES_FILE}..."
chown root:wazuh "$RULES_FILE"
chmod 640 "$RULES_FILE"

echo "[WAZ_025] Redemarrage de wazuh-manager pour appliquer..."
systemctl restart wazuh-manager
if ! wait_for_service_active wazuh-manager 180 5; then
  echo "[WAZ_025] ERREUR : wazuh-manager n'a pas redemarre." >&2
  exit 1
fi

echo "[WAZ_025] OK."
exit 0
