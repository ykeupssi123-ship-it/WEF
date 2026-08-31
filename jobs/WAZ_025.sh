#!/bin/bash
# WAZ_025 - WEF_WAZ_BLD_RULEADDCUSTOM - Regles de detection specifiques
set -uo pipefail
source "$VARS_FILE"
echo "[WAZ_025] Injection des regles personnalisees..."
mkdir -p /var/ossec/etc/rules
cat > /var/ossec/etc/rules/local_rules.xml << RULEEOF
<group name="factory,local,">
  <rule id="100100" level="7">
    <if_group>syscheck</if_group>
    <description>Modification detectee sur un fichier surveille de la Forge</description>
  </rule>
</group>
RULEEOF
echo "[WAZ_025] OK."
exit 0
