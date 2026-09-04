#!/bin/bash
# WAZ_017C - WEF_WAZ_BLD_AUTHCONFIG - Configuration du mode d'authentification Kibana/Wazuh Dashboard
# AJOUTE LE 2026-08-11, REVU LE MEME JOUR (fusion de deux jobs separes
# WAZ_017C_LDAPCONFIG + WAZ_017D_SAMLCONFIG en UN SEUL) suite a une
# question legitime de l'utilisateur : "comment se passe le passage
# d'un mode a l'autre, y compris la DESACTIVATION ?"
#
# Avec deux jobs separes qui n'agissaient CHACUN que dans leur propre
# mode, revenir de ldap/saml vers internal ne nettoyait rien : l'ancien
# domaine LDAP ou SAML restait dans config.yml. Corrige : CE job
# regenere TOUJOURS config.yml (et opensearch_dashboards.yml) EN
# ENTIER a partir de la valeur ACTUELLE de KIBANA_AUTH_MODE, quel
# qu'ait ete le mode precedent - meme principe que LS_024 (sorties
# Logstash) : jamais d'accumulation, jamais de residu d'une execution
# anterieure. Changer de mode = changer KIBANA_AUTH_MODE puis rejouer
# l'orchestrateur, rien d'autre a nettoyer a la main.
#
# MODIFIE LE 2026-08-30 : LDAP_BIND_PASSWORD vient desormais de
# LDAP_BIND_PASSWORD_FILE (jamais vars.conf en clair) - resolu ci-dessous
# uniquement quand MODE=ldap (WAZ_017B a deja verifie sa presence avant
# ce job, mais on ne suppose jamais qu'un job anterieur a bien tourne :
# read_or_generate_secret echoue clairement sinon).
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

MODE="${KIBANA_AUTH_MODE:-internal}"
if [ "$MODE" = "ldap" ]; then
  LDAP_BIND_PASSWORD="$(read_or_generate_secret "$LDAP_BIND_PASSWORD_FILE" non)" || exit 1
fi
SECURITY_DIR="/etc/wazuh-indexer/opensearch-security"
DASH_YML="/etc/wazuh-dashboard/opensearch_dashboards.yml"
mkdir -p "$SECURITY_DIR"

echo "[WAZ_017C] Regeneration complete de la configuration d'authentification (mode : ${MODE})..."

# --- Bloc commun : le compte local reste TOUJOURS actif en secours
# (order 0), quel que soit le mode - pour ne jamais bloquer l'acces
# dehors si LDAP/AD FS est injoignable un jour.
BASIC_BLOCK='      basic_internal_auth_domain:
        description: "Authentification locale (compte de secours '"${WAZ_INDEXER_ADMIN_USER:-admin}"')"
        http_enabled: true
        transport_enabled: true
        order: 0
        http_authenticator:
          type: basic
          challenge: false
        authentication_backend:
          type: internal'

case "$MODE" in
  internal)
    EXTRA_BLOCK=""
    DASH_AUTH_TYPE="basicauth"
    ;;
  ldap)
    SSL_FLAG="false"
    [ "${LDAP_USE_SSL:-false}" = "true" ] && SSL_FLAG="true"
    EXTRA_BLOCK='
      ldap_auth_domain:
        description: "Authentification Active Directory via LDAP (WEF_WAZ_BLD_AUTHCONFIG)"
        http_enabled: true
        transport_enabled: true
        order: 1
        http_authenticator:
          type: basic
          challenge: false
        authentication_backend:
          type: ldap
          config:
            enable_ssl: '"${SSL_FLAG}"'
            enable_start_tls: false
            verify_hostnames: true
            hosts:
              - "'"${LDAP_HOST}:${LDAP_PORT}"'"
            bind_dn: "'"${LDAP_BIND_DN}"'"
            password: "'"${LDAP_BIND_PASSWORD}"'"
            userbase: "'"${LDAP_USER_BASE_DN}"'"
            usersearch: "'"${LDAP_USER_SEARCH_FILTER}"'"
            username_attribute: "sAMAccountName"
            rolebase: "'"${LDAP_ROLE_BASE_DN}"'"
            rolesearch: "'"${LDAP_ROLE_SEARCH_FILTER}"'"'
    DASH_AUTH_TYPE="basicauth"
    ;;
  saml)
    EXTRA_BLOCK='
      saml_auth_domain:
        description: "Authentification SSO via AD FS (WEF_WAZ_BLD_AUTHCONFIG)"
        http_enabled: true
        transport_enabled: false
        order: 1
        http_authenticator:
          type: saml
          challenge: true
          config:
            idp:
              metadata_url: "'"${SAML_IDP_METADATA_URL}"'"
              entity_id: "'"${SAML_IDP_ENTITY_ID}"'"
            sp:
              entity_id: "'"${SAML_SP_ENTITY_ID}"'"
            kibana_url: "'"${SAML_KIBANA_URL}"'"
            roles_key: "'"${SAML_ROLES_KEY}"'"
            exchange_key: "'"$(openssl rand -hex 32 2>/dev/null || echo CHANGEME_EXCHANGE_KEY)"'"
        authentication_backend:
          type: noop'
    DASH_AUTH_TYPE="saml"
    ;;
  *)
    echo "[WAZ_017C] ERREUR : KIBANA_AUTH_MODE='${MODE}' non reconnu (attendu : internal, ldap ou saml)."
    exit 1
    ;;
esac

cat > "${SECURITY_DIR}/config.yml" << YAMLEOF
_meta:
  type: "config"
  config_version: 2

config:
  dynamic:
    http:
      anonymous_auth_enabled: false
    authc:
${BASIC_BLOCK}${EXTRA_BLOCK}
YAMLEOF

if [ -f "$DASH_YML" ]; then
  sed -i '/^opensearch_security\.auth\.type:/d' "$DASH_YML"
  echo "opensearch_security.auth.type: \"${DASH_AUTH_TYPE}\"" >> "$DASH_YML"
  echo "[WAZ_017C] opensearch_security.auth.type: ${DASH_AUTH_TYPE} ecrit dans ${DASH_YML}."
else
  echo "[WAZ_017C] AVERTISSEMENT : ${DASH_YML} introuvable (Wazuh Dashboard pas encore installe ?)."
fi

if [ "$MODE" = "internal" ]; then
  echo "[WAZ_017C] Mode interne : tout residu LDAP/SAML d'un mode precedent a ete efface, seul le compte local reste actif."
else
  echo "[WAZ_017C] Compte de secours local conserve en parallele (basic_internal_auth_domain, order 0) : en cas de probleme, connexion possible avec ${WAZ_INDEXER_ADMIN_USER:-admin} sans etre bloque dehors."
fi
if [ "$MODE" = "saml" ]; then
  echo "[WAZ_017C] RAPPEL : completez le mappage des roles AD FS dans Wazuh Dashboard (Security > Role mappings) apres le premier lancement."
fi

echo "[WAZ_017C] OK."
exit 0
