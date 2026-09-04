#!/bin/bash
# WAZ_017B - WEF_WAZ_BLD_AUTHMODECHECK - Validation du mode d'authentification Kibana/Wazuh Dashboard
# AJOUTE LE 2026-08-11. Verifie que les variables necessaires au mode
# choisi (KIBANA_AUTH_MODE, vars.conf) sont bien remplies AVANT de
# toucher a la moindre configuration - meme logique que PKI_MODE=
# external cote PKI : arreter clairement plutot qu'improviser une
# configuration LDAP/SAML incomplete.
#
# MODIFIE LE 2026-08-30 : LDAP_BIND_PASSWORD vient desormais de
# LDAP_BIND_PASSWORD_FILE (jamais vars.conf en clair) - secret EXTERNE
# (compte de service Active Directory du client), donc verifie ici que
# le FICHIER existe reellement, jamais genere a la place du client.
set -uo pipefail
source "$VARS_FILE"

MODE="${KIBANA_AUTH_MODE:-internal}"
echo "[WAZ_017B] KIBANA_AUTH_MODE=${MODE}"

case "$MODE" in
  internal)
    echo "[WAZ_017B] Mode interne (compte local WAZ_INDEXER_ADMIN_USER) - rien a valider."
    ;;
  ldap)
    MISSING=""
    for v in LDAP_HOST LDAP_BIND_DN LDAP_USER_BASE_DN; do
      [ -z "${!v:-}" ] && MISSING="${MISSING} ${v}"
    done
    if [ -z "${LDAP_BIND_PASSWORD_FILE:-}" ] || [ ! -f "${LDAP_BIND_PASSWORD_FILE:-/dev/null}" ]; then
      MISSING="${MISSING} LDAP_BIND_PASSWORD_FILE(fichier absent : ${LDAP_BIND_PASSWORD_FILE:-non defini})"
    fi
    if [ -n "$MISSING" ]; then
      echo "[WAZ_017B] ERREUR : KIBANA_AUTH_MODE=ldap mais variable(s)/fichier(s) manquant(s) :${MISSING}"
      echo "[WAZ_017B] Demandez ces informations a l'administrateur Active Directory du client avant de continuer."
      exit 1
    fi
    echo "[WAZ_017B] Parametres LDAP presents."
    ;;
  saml)
    MISSING=""
    for v in SAML_IDP_METADATA_URL SAML_SP_ENTITY_ID SAML_KIBANA_URL; do
      [ -z "${!v:-}" ] && MISSING="${MISSING} ${v}"
    done
    if [ -n "$MISSING" ]; then
      echo "[WAZ_017B] ERREUR : KIBANA_AUTH_MODE=saml mais variable(s) manquante(s) dans vars.conf :${MISSING}"
      echo "[WAZ_017B] Demandez ces informations a l'administrateur AD FS du client avant de continuer."
      exit 1
    fi
    echo "[WAZ_017B] Parametres SAML presents."
    ;;
  *)
    echo "[WAZ_017B] ERREUR : KIBANA_AUTH_MODE='${MODE}' non reconnu (attendu : internal, ldap ou saml)."
    exit 1
    ;;
esac

echo "[WAZ_017B] OK."
exit 0
