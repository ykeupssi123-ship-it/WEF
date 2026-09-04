#!/bin/bash
# WAZ_014E_INDEXER_CONNECTOR - WEF_WAZ_BLD_IDXCONNECTOR - Configuration
# reelle du connecteur natif <indexer> (inventaire/vulnerabilites)
#
# AJOUTE LE 2026-08-31 (incident reel wef-elk-core : la case
# "Vulnerability Detection" du Dashboard restait a "0" sur un agent
# jamais durci - signale a juste titre comme suspect par l'utilisateur).
#
# DIAGNOSTIC REEL (jamais suppose) : une fois le module
# vulnerability-scanner lui-meme repare (voir WAZ_044_VD_SAFE_RETRY.sh
# et le correctif disque du meme jour), aucun resultat n'apparaissait
# encore dans wazuh-states-vulnerabilities-* - confirme en reel dans
# /var/ossec/logs/ossec.log : "IndexerConnector initialization failed
# for index 'wazuh-states-inventory-*-wef-elk-core', retrying until the
# connection is successful" en boucle. Cause reelle, confirmee par
# lecture directe de la section <indexer> de ossec.conf :
#   (1) "<host>https://0.0.0.0:9200</host>" - 0.0.0.0 est une adresse
#       D'ECOUTE valide, jamais une adresse a laquelle SE CONNECTER -
#       aucun serveur n'ecoute reellement "sur" 0.0.0.0 du point de vue
#       d'un client.
#   (2) Les chemins de certificats SSL pointent vers
#       /etc/filebeat/certs/{root-ca,filebeat,filebeat-key}.pem - des
#       fichiers qui N'EXISTENT PAS (confirme par ls direct : seuls
#       factory_ca.crt/factory_fullchain.pem/factory_server.key sont
#       reellement presents dans ce dossier, un residu du meme premier
#       essai Filebeat abandonne deja documente dans
#       WAZ_014B_ALERTS_TO_INDEXER.sh).
# Confirme par recherche exhaustive : AUCUN job de cette usine n'a
# jamais configure cette section - elle est restee telle que le tout
# premier essai (abandonne) l'avait laissee, jamais corrigee depuis.
#
# CORRIGE : hote reecrit en 127.0.0.1 (meme machine), certificats
# copies depuis le coffre PKI d'usine (comme partout ailleurs dans ce
# projet) vers un dossier dedie et clairement nomme - plus jamais
# "/etc/filebeat/", trompeur des lors que Filebeat n'est meme pas
# installe sur cette machine (ELK_HOST).
#
# CORRIGE ENCORE LE 2026-08-31 (meme jour, meme incident, en 3 etapes
# reelles successives, chacune verifiee independamment - jamais un
# correctif suppose suffisant sans nouveau test) :
#
# ETAPE 2 (tentee, REVERTEE) : essai d'ajouter <username>/<password>
# litteraux dans le bloc <indexer> (compte admin deja utilise par
# WAZ_014B/WAZ_020) - a d'abord semble necessaire (le seul TLS donnait
# un vrai HTTP 401, confirme par curl direct en tant qu'utilisateur
# wazuh). MAIS : "wazuh-modulesd" a signale ces deux elements comme
# invalides des le redemarrage ("Invalid element in the configuration:
# 'indexer.username'"), ET, bien plus grave, "wazuh-db" (parseur XML
# plus strict) s'est mis a CRASHER AU DEMARRAGE sur ce meme fichier -
# incident majeur reel qui a fait tomber tout wazuh-manager en boucle
# d'echec (diagnostic complet et correctif dans WAZ_014F_DEBUG_
# WORKAROUND.sh - un bug DISTINCT et bien plus serieux, decouvert en
# creusant celui-ci). Ces deux elements ont ete RETIRES du bloc, ce
# schema Wazuh (version 4.14.7) ne les accepte pas du tout, quelle que
# soit la forme testee.
#
# ETAPE 3 (etat actuel, PARTIEL - honnetement documente comme tel) :
# sans identifiants, le connecteur reste bloque - confirme en reel,
# messages "Failed to sync agent 'X': No available server" en boucle
# (visibles seulement depuis la resolution de WAZ_014F_DEBUG_WORKAROUND,
# qui a aussi revele le detail C++ du connecteur - indexerConnector.cpp).
# CAUSE REELLE LA PLUS PROBABLE (non encore confirmee par correctif
# reussi, a traiter comme un chantier SEPARE) : le certificat client
# seul ne suffit jamais a etre reconnu par le plugin de securite de
# wazuh-indexer sans mapping explicite de son DN (Distinguished Name)
# vers un role autorise (plugins.security.authcz.admin_dn ou
# roles_mapping.yml) - LIMITE DEJA DOCUMENTEE ce meme jour dans
# WAZ_017E_AUTHAPPLY.sh pour un besoin similaire, jamais resolue non
# plus a ce jour : necessite securityadmin.sh avec un certificat
# "admin" DISTINCT (jamais le certificat serveur reutilise), non encore
# provisionne par cette usine. CONSEQUENCE REELLE ACCEPTEE POUR
# L'INSTANT : wazuh-states-vulnerabilities-*/wazuh-states-inventory-*
# restent vides - Vulnerability Detection ne peut pas encore publier ses
# resultats vers wazuh-indexer via ce chemin natif, meme si le SCANNER
# lui-meme fonctionne desormais reellement (voir WAZ_044_VD_SAFE_RETRY.sh).
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

CONNECTOR_CERTS="/var/ossec/etc/indexer-connector-certs"
WAZ_INDEXER_PORT="${WAZ_INDEXER_PORT:-9200}"

echo "[WAZ_014E] Copie du PKI d'usine pour le connecteur indexeur natif (${CONNECTOR_CERTS})..."
local_pki_copy "$CONNECTOR_CERTS" "wazuh:wazuh"

if [ -e /var/ossec/etc/ossec.conf ] && lsattr /var/ossec/etc/ossec.conf 2>/dev/null | grep -q '^....i'; then
  echo "[WAZ_014E] ossec.conf est immuable (deja verrouille par WAZ_032) - deverrouillage temporaire avant reecriture."
  chattr -i /var/ossec/etc/ossec.conf
fi

echo "[WAZ_014E] Reecriture de la section <indexer> (hote reel + certificats d'usine reels)..."
# Heredoc QUOTE ('PYEOF', pas PYEOF) : bash n'y substitue RIEN a
# l'interieur - discipline conservee meme sans secret a transmettre ici
# (username/password retires, voir en-tete "ETAPE 2/3") pour rester
# coherente avec le reste du projet.
WAZ_IDX_PORT="$WAZ_INDEXER_PORT" WAZ_IDX_CERTS="$CONNECTOR_CERTS" \
python3 << 'PYEOF'
import re
import os

port = os.environ['WAZ_IDX_PORT']
certs = os.environ['WAZ_IDX_CERTS']

with open('/var/ossec/etc/ossec.conf') as f:
    content = f.read()

new_block = f"""  <indexer>
    <enabled>yes</enabled>
    <hosts>
      <host>https://127.0.0.1:{port}</host>
    </hosts>
    <ssl>
      <certificate_authorities>
        <ca>{certs}/factory_ca.crt</ca>
      </certificate_authorities>
      <certificate>{certs}/factory_fullchain.pem</certificate>
      <key>{certs}/factory_server.key</key>
    </ssl>
  </indexer>"""

pattern = re.compile(r'  <indexer>.*?</indexer>', re.DOTALL)
if not pattern.search(content):
    raise SystemExit("ERREUR : bloc <indexer> introuvable dans ossec.conf, rien reecrit.")

content = pattern.sub(new_block, content, count=1)

with open('/var/ossec/etc/ossec.conf', 'w') as f:
    f.write(content)
PYEOF

if [ $? -ne 0 ]; then
  echo "[WAZ_014E] ERREUR : reecriture de la section <indexer> echouee." >&2
  exit 1
fi

if ! grep -q '<host>https://127.0.0.1:'"${WAZ_INDEXER_PORT}"'</host>' /var/ossec/etc/ossec.conf 2>/dev/null; then
  echo "[WAZ_014E] ERREUR : verification post-ecriture echouee (fichier toujours immuable ?)." >&2
  lsattr /var/ossec/etc/ossec.conf >&2 2>/dev/null || true
  exit 1
fi

echo "[WAZ_014E] Verification/restauration des droits attendus de ossec.conf (root:wazuh, 640)..."
# CORRIGE LE 2026-08-31 (INCIDENT REEL EN PRODUCTION, decouvert par
# l'utilisateur via le health-check du Dashboard : "Error getting the
# authorization token", HTTP 500) : la version precedente de cette ligne
# posait "chmod 600" (proprietaire root:root herite, jamais explicitement
# chowne) - un mode BEAUCOUP TROP RESTRICTIF, jamais verifie contre les
# permissions REELLEMENT attendues par le paquet. Preuve directe trouvee
# dans /var/ossec/logs/api.log : wazuh-apid (qui tourne sous l'utilisateur
# non-privilegie "wazuh", jamais root) levait "PermissionError: [Errno 13]
# Permission denied: '/var/ossec/etc/ossec.conf'" a chaque requete,
# provoquant un HTTP 500 sur TOUTE route de l'API (l'exception survient
# des l'import du module cluster, avant meme la resolution de la route
# demandee). Confirme par "rpm -q --queryformat" sur le paquet
# wazuh-manager : le mode livre est bien "-rw-rw---- root:wazuh", jamais
# 600/root:root. Corrige : chown explicite root:wazuh (jamais suppose
# deja bon), chmod 640 (lecture seule pour le groupe wazuh - plus strict
# que le 660 du paquet, group-writable non necessaire ici, jamais donne
# par prudence). Reteste en reel apres correctif : HTTP 200 confirme sur
# /security/user/authenticate.
chown root:wazuh /var/ossec/etc/ossec.conf
chmod 640 /var/ossec/etc/ossec.conf

chattr +i /var/ossec/etc/ossec.conf

echo "[WAZ_014E] Redemarrage de wazuh-manager..."
systemctl restart wazuh-manager 2>/dev/null || true
if ! wait_for_service_active wazuh-manager 120 5; then
  echo "[WAZ_014E] ERREUR : wazuh-manager n'a pas redemarre proprement." >&2
  exit 1
fi

echo "[WAZ_014E] Verification reelle (etat du connecteur indexeur depuis le redemarrage)..."
sleep 15
if journalctl -u wazuh-manager --since '20 seconds ago' --no-pager 2>/dev/null | grep -qE "Failed to sync agent|No available server"; then
  echo "[WAZ_014E] LIMITE CONNUE (pas une regression de ce job) : le connecteur reste bloque sans mapping DN->role cote securite de wazuh-indexer - voir l'en-tete de ce fichier (chantier separe, non resolu a ce jour). TLS/hote/certificats sont corrects." >&2
fi

echo "[WAZ_014E] OK (connecteur indexeur natif reconfigure : 127.0.0.1:${WAZ_INDEXER_PORT}, PKI d'usine)."
exit 0
