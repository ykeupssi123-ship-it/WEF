#!/bin/bash
# PKI_012_SERVE_CA_HTTP - WEF_PKI_RUN_CAHTTPSRV
# Sert factory_ca.crt (certificat PUBLIC de la CA d'usine) via un petit
# service HTTP permanent, pour que tout AGENT_HOST puisse le recuperer
# tout seul (DIST_001.sh, jobs/lib/, curl), sans identifiant d'aucune
# sorte.
#
# AJOUTE LE 2026-09-13 (demande explicite : "il doit avoir un job qui
# fait ca ... automatique", suite a un DIST_001 bloque en reel sur VM2
# faute d'identifiants SSH). Choix de conception, justifie : un
# certificat de CA est PUBLIC par nature (seule sa cle privee, jamais
# ici, doit rester protegee) - le servir sans authentification n'est
# pas une regression de securite, c'est exactement ce que fait toute
# autorite de certification reelle. Repond aussi au risque deja
# rencontre une fois (2026-08-30, mot de passe root en clair dans
# vars.conf pour ce meme besoin) en supprimant le besoin d'identifiant
# des la racine, plutot que de le proteger mieux.
#
# SECURITE : sert UNIQUEMENT ${PKI_PUBLIC_DIR}, un repertoire DEDIE qui
# ne contient jamais que ce seul fichier - jamais ${PKI_DIR} (qui
# contient la cle privee de la CA et les cles serveur). Verifie
# explicitement ci-dessous qu'aucun autre fichier n'y a jamais ete
# depose avant de (re)demarrer le service.
#
# CORRIGE LE 2026-09-13 (incident reel, premier lancement sur VM1) :
# "python3 -m http.server ... --directory ..." echoue avec
# "unrecognized arguments: --directory" - confirme en reel : Oracle
# Linux 8.10 fournit Python 3.6.8 par defaut, "--directory" n'existe
# que depuis Python 3.7. Corrige sans detecter de version : le service
# demarre deja dans le bon repertoire via "WorkingDirectory=" (unit
# systemd ci-dessous) - "--directory" etait redondant, jamais
# necessaire pour ce besoin precis.
#
# CORRIGE LE 2026-09-13 (meme jour, deuxieme incident reel : DIST_001
# toujours injoignable depuis VM2 malgre un service actif et un port
# ouvert - meme "curl https://.../443" depuis VM2 echouait, alors que
# le ping passait) : port ouvert uniquement sur la zone "public", or
# firewalld fait correspondre une SOURCE avant une INTERFACE - tout le
# trafic venant de BEATS_HOST_IP (VM2) est deja capture par la zone
# "CollectZone" (creee par LS_006, source-bound a BEATS_HOST_IP par
# LS_008), jamais par "public", quel que soit ce que "public" autorise.
# Exactement le meme constat deja documente dans LS_008.sh (incident du
# 2026-08-31, "SSH refuse alors que le ping passe") - CollectZone y est
# explicitement designee comme "le proprietaire unique et complet du
# jeu de ports necessaires a un AGENT_HOST". Corrige : le port est
# desormais aussi ouvert sur CollectZone. Corrige aussi l'ordre dans
# jobs_table.csv (IN_COND passe de PKI_CRYPTO_ARMED a LS_FW_ARMED) :
# CollectZone n'existe pas encore au moment ou PKI_CRYPTO_ARMED est
# rempli (bien avant la phase Logstash) - ce job doit donc jouer APRES
# que CollectZone soit cree ET source-bound, jamais avant.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

CA_FILE="${PKI_DIR}/factory_ca.crt"
[ -f "$CA_FILE" ] || { echo "[PKI_012_SERVE_CA_HTTP] ERREUR : ${CA_FILE} introuvable (PKI_004 doit avoir tourne)." >&2; exit 1; }

mkdir -p "$PKI_PUBLIC_DIR"
cp -f "$CA_FILE" "${PKI_PUBLIC_DIR}/factory_ca.crt"
chmod 755 "$PKI_PUBLIC_DIR"
chmod 644 "${PKI_PUBLIC_DIR}/factory_ca.crt"

# Garde-fou reel, pas suppose : ce repertoire ne doit JAMAIS contenir
# autre chose que ce seul fichier public, quelle que soit la cause
# (erreur de copie manuelle, script tiers...).
EXTRA=$(find "$PKI_PUBLIC_DIR" -maxdepth 1 -type f ! -name 'factory_ca.crt')
if [ -n "$EXTRA" ]; then
  echo "[PKI_012_SERVE_CA_HTTP] ERREUR : fichier(s) inattendu(s) dans ${PKI_PUBLIC_DIR} (repertoire cense ne contenir QUE factory_ca.crt) :" >&2
  echo "$EXTRA" >&2
  exit 1
fi

UNIT_FILE="/etc/systemd/system/wef-ca-server.service"
cat > "$UNIT_FILE" << UNITEOF
[Unit]
Description=WEF - Distribution HTTP du certificat public de la CA d'usine
After=network.target

[Service]
Type=simple
WorkingDirectory=${PKI_PUBLIC_DIR}
ExecStart=/usr/bin/python3 -m http.server ${PKI_CA_HTTP_PORT} --bind 0.0.0.0
Restart=on-failure
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
UNITEOF

systemctl daemon-reload
systemctl enable --now wef-ca-server

echo "[PKI_012_SERVE_CA_HTTP] Ouverture du port ${PKI_CA_HTTP_PORT}/tcp sur CollectZone (seule zone reellement appliquee au trafic venant d'un AGENT_HOST - firewalld fait correspondre une source avant une interface, meme constat que LS_008.sh) et sur public (acces direct/local)..."
firewall-cmd --permanent --zone=CollectZone --add-port="${PKI_CA_HTTP_PORT}/tcp"
firewall-cmd --permanent --zone=public --add-port="${PKI_CA_HTTP_PORT}/tcp"
firewall-cmd --reload

echo "[PKI_012_SERVE_CA_HTTP] Verification reelle (requete locale, comparaison au fichier source)..."
if ! curl -sf "http://127.0.0.1:${PKI_CA_HTTP_PORT}/factory_ca.crt" -o "${WORK_TMP_DIR}/pki012_check.crt"; then
  echo "[PKI_012_SERVE_CA_HTTP] ERREUR : le service HTTP ne repond pas sur le port ${PKI_CA_HTTP_PORT}." >&2
  systemctl status wef-ca-server --no-pager 2>&1 | tail -20 >&2
  exit 1
fi
if ! cmp -s "$CA_FILE" "${WORK_TMP_DIR}/pki012_check.crt"; then
  echo "[PKI_012_SERVE_CA_HTTP] ERREUR : le fichier servi differe du certificat reel." >&2
  rm -f "${WORK_TMP_DIR}/pki012_check.crt"
  exit 1
fi
rm -f "${WORK_TMP_DIR}/pki012_check.crt"

echo "[PKI_012_SERVE_CA_HTTP] OK (verifie : contenu servi identique au certificat reel)."
exit 0
