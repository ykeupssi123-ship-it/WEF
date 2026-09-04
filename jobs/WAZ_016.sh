#!/bin/bash
# WAZ_016 - WEF_WAZ_BLD_STARTDSHBRD - Demarrage de l'interface native isolee
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

# AJOUTE LE 2026-08-30 (incident reel wef-elk-core, premier passage complet
# de la chaine jusqu'a WAZ_039_MODE_SOUVERAIN) : wazuh-dashboard.service
# tombait en boucle de redemarrage (systemd "restart counter" grimpant sans
# fin, RestartSec=100ms) - INVISIBLE pour "systemctl restart" ci-dessous
# (accepte immediatement, avant que le crash n'ait meme eu lieu) ET pour
# "systemctl is-active" ailleurs dans la chaine (WAZ_039), qui peut
# recevoir "active" pendant la fenetre de quelques centaines de ms ou
# systemd relance le process avant qu'il ne s'ecroule a nouveau -
# confirme en reel par `journalctl -u wazuh-dashboard`, message explicite :
# "Error: ENOENT: no such file or directory, open
# '/etc/wazuh-dashboard/certs/dashboard-key.pem'". Cause reelle trouvee :
# opensearch_dashboards.yml (fourni par le paquet, jamais modifie par
# cette usine) reference en dur trois fichiers PEM sous
# /etc/wazuh-dashboard/certs/ (dashboard-key.pem, dashboard.pem,
# root-ca.pem) qu'AUCUN job de cette usine, ni le paquet RPM lui-meme
# (confirme : "rpm -ql wazuh-dashboard" ne les liste pas), n'a jamais
# generes - contrairement a Elasticsearch/Logstash/wazuh-indexer, qui
# recoivent tous les trois leur copie via local_pki_copy() (lib/commun.sh)
# dans leurs jobs respectifs. Cette lacune existait donc depuis l'origine
# de cette usine (jamais couverte par un job), simplement jamais revelee
# avant ce premier passage complet et reel de la chaine jusqu'ici.
# Corrige : ce job fournit desormais lui-meme le PKI d'usine a
# wazuh-dashboard, sous les noms de fichiers EXACTS attendus par le yml
# du paquet (jamais touche par ailleurs) - meme materiel (factory_ca.crt/
# factory_server.key/factory_fullchain.pem) que tous les autres
# composants, simple renommage local pour matcher la convention du
# paquet, propriete wazuh-dashboard:wazuh-dashboard (utilisateur reel du
# service, confirme par `systemctl show -p User -p Group`).
DASH_CERTS="/etc/wazuh-dashboard/certs"
mkdir -p "$DASH_CERTS"
cp -f "${PKI_DIR}/factory_server.key" "${DASH_CERTS}/dashboard-key.pem"
cp -f "${PKI_DIR}/factory_fullchain.pem" "${DASH_CERTS}/dashboard.pem"
cp -f "${PKI_DIR}/factory_ca.crt" "${DASH_CERTS}/root-ca.pem"
chown wazuh-dashboard:wazuh-dashboard "$DASH_CERTS" "${DASH_CERTS}"/*.pem
chmod 750 "$DASH_CERTS"
chmod 640 "${DASH_CERTS}/dashboard-key.pem"
chmod 644 "${DASH_CERTS}/dashboard.pem" "${DASH_CERTS}/root-ca.pem"
echo "[WAZ_016] PKI d'usine fourni a wazuh-dashboard (${DASH_CERTS})."

# AJOUTE LE 2026-08-30 (meme incident reel, diagnostic pousse plus loin
# une fois le crash-loop de certificats resolu ci-dessus) : une fois le
# service stable, il restait bloque en HTTP 503 permanent
# ("[ResponseError]: Response Error" en boucle dans son propre journal,
# cote plugin "opensearch") - cause reelle : opensearch_dashboards.yml
# (fourni par le paquet, jamais complete par cette usine) porte
# "#opensearch.username:"/"#opensearch.password:" EN COMMENTAIRE - la
# connexion INTERNE serveur-a-serveur du dashboard vers wazuh-indexer
# (distincte de l'authentification des utilisateurs finaux au
# navigateur, deja geree par WAZ_017C/KIBANA_AUTH_MODE) n'a jamais eu
# d'identifiants, alors que le plugin de securite de wazuh-indexer les
# exige (confirme : /etc/wazuh-indexer/opensearch-security/
# internal_users.yml ne definit qu'un seul compte, "admin" - aucun
# compte de service "kibanaserver" dedie n'existe dans ce projet).
# Corrige, dans le meme esprit que le reste de cette usine (un seul
# compte admin partage, jamais de compte de service separe a gerer en
# plus) : le compte administrateur de l'indexeur (WAZ_INDEXER_ADMIN_USER/
# WAZ_INDEXER_ADMIN_PASSWORD_FILE, deja utilise par WAZ_014A/WAZ_020/
# WAZ_014B) sert aussi de compte de service pour cette connexion
# interne. Lignes existantes (commentees ou non) retirees puis
# reecrites - jamais d'accumulation (meme principe que WAZ_017C).
WAZUH_INDEXER_ADMIN_PW="$(read_or_generate_secret "$WAZ_INDEXER_ADMIN_PASSWORD_FILE" non)" || exit 1
DASH_YML="/etc/wazuh-dashboard/opensearch_dashboards.yml"
if [ -f "$DASH_YML" ]; then
  sed -i '/^#\?opensearch\.username:/d; /^#\?opensearch\.password:/d' "$DASH_YML"
  {
    echo "opensearch.username: \"${WAZ_INDEXER_ADMIN_USER}\""
    echo "opensearch.password: \"${WAZUH_INDEXER_ADMIN_PW}\""
  } >> "$DASH_YML"
  echo "[WAZ_016] Identifiants de connexion interne vers wazuh-indexer ecrits dans ${DASH_YML}."
else
  echo "[WAZ_016] AVERTISSEMENT : ${DASH_YML} introuvable, identifiants internes non ecrits."
fi

# CORRECTIF 2026-08-19 (meme famille d'incident reel que LS_026_FINAL,
# wef-elk-core) : "systemctl enable --now" ne redemarre pas un service
# deja actif. Enable + restart explicite.
#
# CORRIGE LE 2026-08-30 : "systemctl restart" reussissait toujours (il ne
# fait qu'accepter la demande), meme quand le service partait ensuite en
# boucle de crash immediate - jamais detecte avant ce jour car jamais
# suivi d'une verification de STABILITE (juste "restart" puis "OK").
# Ajout de wait_for_service_active (lib/commun.sh, meme garde-fou que
# WAZ_015/WAZ_035/WAZ_039).
echo "[WAZ_016] Demarrage de wazuh-dashboard..."
systemctl enable wazuh-dashboard 2>/dev/null || true
systemctl restart wazuh-dashboard 2>/dev/null || true
if ! wait_for_service_active wazuh-dashboard 120 5; then
  echo "[WAZ_016] ERREUR : wazuh-dashboard.service n'a pas pu etre confirme actif et stable. Diagnostic (journalctl -u wazuh-dashboard -n 30) :" >&2
  journalctl -u wazuh-dashboard -n 30 --no-pager 2>/dev/null || true
  exit 1
fi
echo "[WAZ_016] OK."
exit 0
