#!/bin/bash
# WAZ_014A - WEF_WAZ_RUN_INDXRADMINPW - Alignement du mot de passe admin du moteur de stockage
#
# AJOUTE LE 2026-08-20, suite directe de WAZ_013C (voir son en-tete pour
# le diagnostic complet). Ce job est celui qui pousse REELLEMENT le mot
# de passe defini dans vars.conf (WAZ_INDEXER_ADMIN_PASSWORD) vers le
# cluster wazuh-indexer EN COURS D'EXECUTION - ne peut se faire qu'APRES
# le demarrage du moteur (WAZ_014), contrairement a WAZ_013C (le
# certificat, lui, peut etre prepare avant le demarrage).
#
# Idempotent par verification reelle (jamais suppose) : si le mot de
# passe actuellement dans vars.conf fonctionne DEJA contre le cluster
# (cas d'une reexecution, ou d'un cluster deploye avant cet incident et
# deja corrige manuellement), rien n'est refait. Sinon, utilise l'outil
# officiel embarque wazuh-passwords-tool.sh avec le certificat client
# prepare par WAZ_013C, PUIS reverifie par un appel reel (le WARNING
# affiche par l'outil ne prouve rien a lui seul - deja vu en reel :
# "WARNING: Password changed" s'affiche meme quand la vraie propagation
# a echoue faute de certificat).
#
# MODIFIE LE 2026-08-30 : WAZ_INDEXER_ADMIN_PASSWORD ne vient plus d'une
# valeur en clair dans vars.conf mais de WAZ_INDEXER_ADMIN_PASSWORD_FILE
# (voir vars.conf et lib/commun.sh, read_or_generate_secret) - genere
# automatiquement ICI, au tout premier passage, si le fichier n'existe
# pas encore : c'est ce job (celui qui pousse reellement le mot de passe
# au cluster) qui est responsable de le creer, pas un autre.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

WAZ_INDEXER_ADMIN_PASSWORD="$(read_or_generate_secret "$WAZ_INDEXER_ADMIN_PASSWORD_FILE" oui)" || exit 1

# CORRIGE LE 2026-08-30 : ES_PORT designe Elasticsearch (vars.conf) -
# wazuh-indexer a son propre port depuis WAZ_013D_INDXR_PORTS.sh
# (incident reel de collision de port, voir son en-tete).
WAZ_INDEXER_PORT="${WAZ_INDEXER_PORT:-9201}"
TOOL="/usr/share/wazuh-indexer/plugins/opensearch-security/tools/wazuh-passwords-tool.sh"
ADMIN_CERT="/etc/wazuh-indexer/certs/admin.pem"
ADMIN_KEY="/etc/wazuh-indexer/certs/admin-key.pem"
LOGFILE="${WORK_TMP_DIR}/waz014a_pwtool.log"

check_auth(){
  curl -sk -u "${WAZ_INDEXER_ADMIN_USER}:${WAZ_INDEXER_ADMIN_PASSWORD}" \
    -o /dev/null -w "%{http_code}" \
    "https://127.0.0.1:${WAZ_INDEXER_PORT}/_cluster/health"
}

echo "[WAZ_014A] Verification : le mot de passe actuel de vars.conf fonctionne-t-il deja ?"
HTTP_CODE=$(check_auth)
if [ "$HTTP_CODE" = "200" ]; then
  echo "[WAZ_014A] Authentification deja OK (HTTP 200) - rien a faire."
  echo "[WAZ_014A] OK."
  exit 0
fi
echo "[WAZ_014A] Authentification en echec (HTTP ${HTTP_CODE}), alignement necessaire."

if [ ! -f "$TOOL" ]; then
  echo "[WAZ_014A] ERREUR : ${TOOL} introuvable - le paquet wazuh-indexer est-il bien installe ?" >&2
  exit 1
fi
if [ ! -r "$ADMIN_CERT" ] || [ ! -r "$ADMIN_KEY" ]; then
  echo "[WAZ_014A] ERREUR : ${ADMIN_CERT} et/ou ${ADMIN_KEY} absents ou illisibles - WAZ_013C a-t-il bien tourne avant ce job ?" >&2
  exit 1
fi

echo "[WAZ_014A] Poussee du mot de passe (WAZ_INDEXER_ADMIN_USER=${WAZ_INDEXER_ADMIN_USER}) via wazuh-passwords-tool.sh..."
bash "$TOOL" -u "${WAZ_INDEXER_ADMIN_USER}" -p "${WAZ_INDEXER_ADMIN_PASSWORD}" \
  -c "$ADMIN_CERT" -k "$ADMIN_KEY" -v > "$LOGFILE" 2>&1
TOOL_RC=$?
if [ "$TOOL_RC" -ne 0 ]; then
  echo "[WAZ_014A] AVERTISSEMENT : wazuh-passwords-tool.sh a rendu un code de sortie non nul (${TOOL_RC}) - voir ${LOGFILE}. Verification reelle en cours quand meme."
fi

echo "[WAZ_014A] Verification post-poussee (jamais suppose que le WARNING de l'outil signifie un succes reel)..."
HTTP_CODE=$(check_auth)
if [ "$HTTP_CODE" != "200" ]; then
  echo "[WAZ_014A] ERREUR : authentification toujours en echec (HTTP ${HTTP_CODE}) apres wazuh-passwords-tool.sh. Voir ${LOGFILE} pour le detail (chercher 'ERR:' ou 'Exception')." >&2
  exit 1
fi

echo "[WAZ_014A] Verifie : authentification OK (HTTP 200) avec le mot de passe de vars.conf."
rm -f "$LOGFILE"
echo "[WAZ_014A] OK."
exit 0
