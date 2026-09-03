#!/bin/bash
# WAZ_025 - WEF_WAZ_BLD_RULEADDCUSTOM - Regles de detection specifiques
set -uo pipefail
source "$VARS_FILE"
echo "[WAZ_025] Injection des regles personnalisees..."

# CORRIGE LE 2026-09-03 (incident reel decouvert en corrigeant WAZ_019_FLOOD,
# voir docs/JOURNAL_TECHNIQUE.md) : ce job faisait un "cat > local_rules.xml"
# INCONDITIONNEL - si un autre job (numeriquement plus petit, donc deja
# execute, comme WAZ_019_FLOOD qui ajoute desormais sa propre regle a ce
# meme fichier partage) avait deja ajoute la sienne, ce job l'ecrasait
# silencieusement en repartant d'un fichier ne contenant QUE la regle
# 100100. Meme principe idempotent/additif que WAZ_041_ALERT_CANARY.sh
# (seul autre job a toucher ce fichier a ce jour) : plus jamais un "cat >",
# toujours une insertion verifiee.
RULES_FILE="/var/ossec/etc/rules/local_rules.xml"
mkdir -p "$(dirname "$RULES_FILE")"
if [ ! -f "$RULES_FILE" ]; then
  cat > "$RULES_FILE" << 'RULEEOF'
<group name="factory,local,">
</group>
RULEEOF
fi
if ! grep -q 'id="100100"' "$RULES_FILE" 2>/dev/null; then
  sed -i 's#</group>#  <rule id="100100" level="7">\n    <if_group>syscheck</if_group>\n    <description>Modification detectee sur un fichier surveille de la Forge</description>\n  </rule>\n</group>#' "$RULES_FILE"
else
  echo "[WAZ_025] Regle 100100 deja presente, ignore."
fi
echo "[WAZ_025] OK."
exit 0
