#!/bin/bash
# DIST_001 - WEF_BEATS_BLD_CADIST
# Distribution automatique du certificat de la CA d'usine (factory_ca.crt)
# depuis la VM ELK_HOST vers la VM BEATS_HOST. Sur VM1, tous les services
# (ES/LS/KB/WAZ) partagent deja le meme repertoire local ${PKI_DIR} : rien
# a distribuer entre eux. Sur VM2, Filebeat/Metricbeat sont sur une machine
# PHYSIQUEMENT DIFFERENTE et n'ont aucun moyen de lire ce repertoire sans
# une copie explicite : c'est ce que fait ce job, au premier lancement de
# l'orchestrateur sur VM2.
#
# Ne s'execute que sur ROLE=AGENT_HOST, et seulement si FILEBEAT ou
# METRICBEAT figure dans AGENT_COMPONENTS (voir jobs_table.csv,
# colonne COMPONENT="FILEBEAT|METRICBEAT"). Prerequis pour FB_005 et
# MB_005 (verification de presence du coffre PKI).
#
# Authentification : cle SSH recommandee (FACTORY_SSH_KEY). Un mot de
# passe (FACTORY_SSH_PASSWORD_FILE) est accepte en secours mais n'est
# JAMAIS ecrit par ces scripts : vous le deposez vous-meme, localement,
# dans secrets/factory_ssh_password.txt sur VM2 uniquement - il ne doit
# jamais transiter ailleurs.
#
# MODIFIE LE 2026-08-30 : FACTORY_SSH_PASSWORD venait auparavant d'une
# valeur en clair dans vars.conf (livree telle quelle dans l'archive de
# deploiement - incident reel decouvert lors de l'audit de la reprise
# WAZ_020_VERIFY, voir vars.conf). Vient desormais de
# FACTORY_SSH_PASSWORD_FILE - secret EXTERNE (compte deja existant sur
# VM2), jamais genere automatiquement.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

if [ "${ROLE}" != "AGENT_HOST" ]; then
  echo "[DIST_001] ROLE=${ROLE}, ce job ne concerne que AGENT_HOST. Ignore."
  echo "[DIST_001] OK."
  exit 0
fi

if [ -z "${FACTORY_HOST_IP:-}" ]; then
  echo "[DIST_001] ERREUR : FACTORY_HOST_IP est vide dans vars.conf. Impossible de savoir ou recuperer la CA."
  exit 1
fi

mkdir -p "${PKI_DIR}"

if [ -f "${PKI_DIR}/factory_ca.crt" ]; then
  echo "[DIST_001] factory_ca.crt deja present localement, distribution ignoree."
  echo "[DIST_001] OK."
  exit 0
fi

SSH_USER="${FACTORY_SSH_USER:-root}"
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=8"

echo "[DIST_001] Recuperation de factory_ca.crt depuis ${SSH_USER}@${FACTORY_HOST_IP}..."

if [ -n "${FACTORY_SSH_KEY:-}" ] && [ -f "${FACTORY_SSH_KEY}" ]; then
  scp $SSH_OPTS -i "${FACTORY_SSH_KEY}" \
    "${SSH_USER}@${FACTORY_HOST_IP}:${PKI_DIR}/factory_ca.crt" "${PKI_DIR}/factory_ca.crt"
elif [ -n "${FACTORY_SSH_PASSWORD_FILE:-}" ] && [ -f "${FACTORY_SSH_PASSWORD_FILE}" ]; then
  echo "[DIST_001] AVERTISSEMENT : authentification par mot de passe (moins sur qu'une cle SSH)."
  command -v sshpass >/dev/null || { echo "[DIST_001] ERREUR : sshpass n'est pas installe (apt/dnf install sshpass) pour utiliser FACTORY_SSH_PASSWORD_FILE."; exit 1; }
  FACTORY_SSH_PASSWORD="$(read_or_generate_secret "$FACTORY_SSH_PASSWORD_FILE" non)" || exit 1
  sshpass -p "${FACTORY_SSH_PASSWORD}" scp $SSH_OPTS \
    "${SSH_USER}@${FACTORY_HOST_IP}:${PKI_DIR}/factory_ca.crt" "${PKI_DIR}/factory_ca.crt"
else
  echo "[DIST_001] ERREUR : ni FACTORY_SSH_KEY ni FACTORY_SSH_PASSWORD_FILE renseignes sur cette machine (VM2)."
  echo "[DIST_001] Renseignez l'un des deux localement (secrets/factory_ssh_password.txt pour le second), ou copiez manuellement factory_ca.crt depuis VM1 vers ${PKI_DIR}/ puis relancez."
  exit 1
fi

chmod 644 "${PKI_DIR}/factory_ca.crt"
echo "[DIST_001] CA recue et installee dans ${PKI_DIR}."
echo "[DIST_001] OK."
exit 0
