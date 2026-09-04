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

# AJOUTE LE 2026-09-03, suite a un incident reel (deploiement MIPREL, voir
# docs/JOURNAL_TECHNIQUE.md) : wazuh-passwords-tool.sh fait un "securityadmin
# -backup" AVANT de pousser le nouveau mot de passe, puis ecrase
# inconditionnellement internal_users.yml avec ce backup - meme si le backup
# a echoue ("empty source"). Si un premier passage a deja eu lieu pendant que
# l'index de securite n'etait pas encore pret, ce vide se grave alors de
# facon PERMANENTE dans l'index : chaque tentative suivante retrouve le meme
# vide, meme cluster GREEN, boucle infinie de 503 sur _cluster/health. Aucune
# quantite de reessais ne repare ca seule - il faut repousser une config par
# defaut saine AVANT de rappeler l'outil. Detecte et repare ICI pour qu'un
# futur deploiement (VM differente, etudiant, MIPREL) ne reste jamais bloque
# sans intervention manuelle.
INTERNAL_USERS_YML="/etc/wazuh-indexer/opensearch-security/internal_users.yml"
if [ ! -s "$INTERNAL_USERS_YML" ]; then
  echo "[WAZ_014A] ALERTE : ${INTERNAL_USERS_YML} est vide - incident connu (voir docs/JOURNAL_TECHNIQUE.md, 2026-09-03). Restauration depuis le paquet RPM d'origine avant de continuer..."

  RPM_NVRA="$(rpm -q --queryformat '%{name}-%{version}-%{release}.%{arch}.rpm\n' wazuh-indexer 2>/dev/null)"
  if [ -z "$RPM_NVRA" ]; then
    echo "[WAZ_014A] ERREUR : impossible de determiner le paquet wazuh-indexer installe (rpm -q a echoue)." >&2
    exit 1
  fi
  RPM_PATH="$(find /var/cache/dnf /var/cache/yum -iname "$RPM_NVRA" 2>/dev/null | head -1)"
  # CORRIGE LE 2026-09-04 (incident reel, meme deploiement, VM neuve) :
  # le cache DNF/YUM peut avoir ete legitimement purge entre-temps
  # (INFRA_005_DISK_HYGIENE fait exactement ca, "purge cache dnf" - pas
  # un accident, un entretien voulu). Ne jamais abandonner sur ce seul
  # constat : retelecharge le MEME NVRA exact depuis le depot officiel
  # (deja configure, WAZ_009) avant de renoncer.
  if [ -z "$RPM_PATH" ]; then
    echo "[WAZ_014A] Paquet absent du cache local (probablement purge par l'entretien disque) - retelechargement depuis le depot officiel..."
    DL_DIR="$(mktemp -d)"
    dnf download --downloaddir="$DL_DIR" wazuh-indexer >/dev/null 2>&1 || true
    RPM_PATH="$(find "$DL_DIR" -iname "$RPM_NVRA" 2>/dev/null | head -1)"
  fi
  if [ -z "$RPM_PATH" ]; then
    echo "[WAZ_014A] ERREUR : ${INTERNAL_USERS_YML} est vide, le paquet d'origine (${RPM_NVRA}) est introuvable en cache DNF/YUM ET le retelechargement depuis le depot a echoue - restauration manuelle necessaire (voir docs/JOURNAL_TECHNIQUE.md)." >&2
    exit 1
  fi

  RESTORE_DIR="$(mktemp -d)"
  ( cd "$RESTORE_DIR" && rpm2cpio "$RPM_PATH" | cpio -idm "./etc/wazuh-indexer/opensearch-security/*.yml" ) >/dev/null 2>&1
  RESTORED=0
  for f in "$RESTORE_DIR"/etc/wazuh-indexer/opensearch-security/*.yml; do
    [ -s "$f" ] || continue
    dest="/etc/wazuh-indexer/opensearch-security/$(basename "$f")"
    [ -s "$dest" ] && continue
    cp -f "$f" "$dest"
    chown wazuh-indexer:wazuh-indexer "$dest"
    chmod 640 "$dest"
    echo "[WAZ_014A] Restaure depuis le paquet RPM : ${dest}"
    RESTORED=$((RESTORED+1))
  done
  rm -rf "$RESTORE_DIR"
  if [ "$RESTORED" -eq 0 ] || [ ! -s "$INTERNAL_USERS_YML" ]; then
    echo "[WAZ_014A] ERREUR : la restauration depuis ${RPM_PATH} n'a pas rempli ${INTERNAL_USERS_YML}." >&2
    exit 1
  fi

  echo "[WAZ_014A] Rechargement de la configuration de securite par defaut dans l'index (securityadmin.sh -cd)..."
  CD_CACERT="$(grep 'plugins.security.ssl.transport.pemtrustedcas_filepath:' /etc/wazuh-indexer/opensearch.yml | awk '{print $2}')"
  CD_LOG="${WORK_TMP_DIR}/waz014a_securityadmin_cd.log"
  # NOTE : port 9200 ici (pas ${WAZ_INDEXER_PORT}=9201) - c'est le port de
  # transport que securityadmin.sh utilise reellement pour parler a
  # opensearch-security, distinct du port REST verifie par check_auth().
  # Prouve fonctionnel en reel le 2026-09-03 (log wazuh-passwords-tool.sh :
  # "Will connect to localhost:9200 ... done", cluster GREEN).
  JAVA_HOME=/usr/share/wazuh-indexer/jdk/ OPENSEARCH_CONF_DIR=/etc/wazuh-indexer \
    /usr/share/wazuh-indexer/plugins/opensearch-security/tools/securityadmin.sh \
    -cd /etc/wazuh-indexer/opensearch-security/ -icl -nhnv \
    -cacert "$CD_CACERT" -cert "$ADMIN_CERT" -key "$ADMIN_KEY" \
    -h localhost -p 9200 > "$CD_LOG" 2>&1
  if ! grep -q "Done with success" "$CD_LOG"; then
    echo "[WAZ_014A] ERREUR : le rechargement de la configuration par defaut a echoue - voir ${CD_LOG}." >&2
    cat "$CD_LOG" >&2
    exit 1
  fi
  rm -f "$CD_LOG"
  echo "[WAZ_014A] Configuration de securite par defaut rechargee (admin/mot de passe de demonstration actif temporairement - remplace ci-dessous)."
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
