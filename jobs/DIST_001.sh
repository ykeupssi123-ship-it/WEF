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
# REFAIT LE 2026-09-13 (incident reel : bloque sur une vraie VM2, faute
# de FACTORY_SSH_KEY/FACTORY_SSH_PASSWORD_FILE ; demande explicite de
# l'operateur : "il doit avoir un job qui fait ca ... automatique",
# aucune manipulation manuelle acceptee). Ancienne conception (scp/
# sshpass, un identifiant SSH partage entre les deux VM) abandonnee :
# jamais automatisable sans le deposer manuellement quelque part
# d'abord, et deja source d'un incident reel (2026-08-30, mot de passe
# root en clair dans vars.conf). Repense a la racine : factory_ca.crt
# est un certificat PUBLIC (la cle privee, jamais distribuee, reste
# protegee dans PKI_DIR sur VM1) - PKI_012_SERVE_CA_HTTP (ELK_HOST) le
# sert desormais en HTTP simple, sans authentification (aucune
# regression de securite : c'est exactement ce que fait toute autorite
# de certification reelle). Ce job se contente de le recuperer par
# curl, en reessayant reellement jusqu'a ce que VM1 reponde - controle
# explicite de la disponibilite de VM1, jamais un seul essai a froid.
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

CA_URL="http://${FACTORY_HOST_IP}:${PKI_CA_HTTP_PORT}/factory_ca.crt"
TMP_CRT="${WORK_TMP_DIR}/dist001_factory_ca.crt"

echo "[DIST_001] Recuperation de factory_ca.crt depuis ${CA_URL} (ELK_HOST doit avoir joue PKI_012_SERVE_CA_HTTP)..."
OBTENU=0
for tentative in $(seq 1 24); do
  if curl -sf --connect-timeout 5 "$CA_URL" -o "$TMP_CRT"; then
    OBTENU=1
    break
  fi
  echo "[DIST_001] ELK_HOST (${FACTORY_HOST_IP}:${PKI_CA_HTTP_PORT}) pas encore joignable (essai ${tentative}/24), nouvel essai dans 5s..."
  sleep 5
done

if [ "$OBTENU" -ne 1 ]; then
  echo "[DIST_001] ERREUR : impossible de joindre ${CA_URL} apres 24 essais (2 minutes)." >&2
  echo "[DIST_001] Verifiez que PKI_012_SERVE_CA_HTTP a bien tourne sur ELK_HOST (\$APP_BIN/history.sh PKI_012_SERVE_CA_HTTP depuis VM1) et que le port ${PKI_CA_HTTP_PORT} est joignable depuis cette machine (firewall/reseau)." >&2
  rm -f "$TMP_CRT"
  exit 1
fi

# Verification reelle du contenu, jamais une simple presence de fichier
# (meme discipline que PKI_003-009 cote ELK_HOST) : un serveur HTTP qui
# repond 200 avec une page d'erreur ou un fichier vide ne doit jamais
# etre accepte comme un vrai certificat.
if ! openssl x509 -noout -in "$TMP_CRT" 2>/dev/null; then
  echo "[DIST_001] ERREUR : le contenu recupere n'est pas un certificat X.509 valide." >&2
  rm -f "$TMP_CRT"
  exit 1
fi

mv "$TMP_CRT" "${PKI_DIR}/factory_ca.crt"
chmod 644 "${PKI_DIR}/factory_ca.crt"
echo "[DIST_001] CA recue, validee (certificat X.509 reel) et installee dans ${PKI_DIR}."
echo "[DIST_001] OK."
exit 0
