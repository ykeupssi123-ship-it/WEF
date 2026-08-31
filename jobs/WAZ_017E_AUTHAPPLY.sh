#!/bin/bash
# WAZ_017E - WEF_WAZ_RUN_AUTHAPPLY - Application du mode d'authentification choisi
# AJOUTE LE 2026-08-11. Si KIBANA_AUTH_MODE=internal, rien a faire (le
# fichier config.yml d'origine n'a pas ete touche par WAZ_017C/017D).
# Sinon, redemarre wazuh-indexer et wazuh-dashboard pour qu'ils
# relisent leur configuration.
#
# LIMITE CONNUE, A NE PAS MASQUER : sur un cluster deja initialise
# (index de securite .opendistro_security deja cree), le plugin de
# securite OpenSearch ne relit PAS automatiquement config.yml au
# redemarrage - il faut pousser le changement avec securityadmin.sh,
# qui exige un certificat client "admin" (admin_dn) distinct du
# certificat serveur genere par ce projet (PKI_003-008). Cette usine
# ne provisionne pas encore ce certificat admin separe : la commande
# exacte est affichee ci-dessous a titre de RAPPEL MANUEL, pas
# executee automatiquement, pour ne pas faire croire a une bascule
# reussie qui n'a pas eu lieu.
set -uo pipefail
source "$VARS_FILE"

MODE="${KIBANA_AUTH_MODE:-internal}"

if [ "$MODE" = "internal" ]; then
  echo "[WAZ_017E] KIBANA_AUTH_MODE=internal, rien a appliquer."
  echo "[WAZ_017E] OK."
  exit 0
fi

echo "[WAZ_017E] Redemarrage de wazuh-indexer et wazuh-dashboard (mode ${MODE})..."
systemctl restart wazuh-indexer 2>/dev/null || echo "[WAZ_017E] AVERTISSEMENT : redemarrage wazuh-indexer a echoue ou service absent."
sleep 5
systemctl restart wazuh-dashboard 2>/dev/null || echo "[WAZ_017E] AVERTISSEMENT : redemarrage wazuh-dashboard a echoue ou service absent."

echo "[WAZ_017E] --------------------------------------------------------------"
echo "[WAZ_017E] ETAPE MANUELLE RESTANTE (sur un cluster deja initialise) :"
echo "[WAZ_017E]   /usr/share/wazuh-indexer/plugins/opensearch-security/tools/securityadmin.sh \\"
echo "[WAZ_017E]     -cd /etc/wazuh-indexer/opensearch-security/ \\"
echo "[WAZ_017E]     -icl -nhnv \\"
echo "[WAZ_017E]     -cacert \${PKI_DIR}/factory_ca.crt \\"
echo "[WAZ_017E]     -cert   <certificat_client_admin_a_provisionner> \\"
echo "[WAZ_017E]     -key    <cle_client_admin_a_provisionner> \\"
echo "[WAZ_017E]     -h 127.0.0.1"
echo "[WAZ_017E]   (necessite un certificat 'admin' distinct, avec son DN"
echo "[WAZ_017E]    reference dans plugins.security.authcz.admin_dn - non"
echo "[WAZ_017E]    encore provisionne par ce projet, a ajouter avant la"
echo "[WAZ_017E]    premiere mise en production LDAP/SAML)."
echo "[WAZ_017E] --------------------------------------------------------------"
echo "[WAZ_017E] OK."
exit 0
