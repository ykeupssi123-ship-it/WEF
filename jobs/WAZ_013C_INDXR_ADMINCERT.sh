#!/bin/bash
# WAZ_013C - WEF_WAZ_BLD_INDXRADMINCERT - Certificat client "admin" du moteur de stockage
#
# AJOUTE LE 2026-08-20 (incident reel wef-elk-core, WAZ_020_VERIFY -> 401
# security_exception "unable to authenticate user [admin]"). Diagnostic
# mene par reproduction manuelle exacte (jamais suppose) :
#   - vars.conf definissait WAZ_INDEXER_ADMIN_PASSWORD="admin", qui ne
#     respecte meme pas la politique de mot de passe de Wazuh (majuscule
#     + minuscule + chiffre + symbole parmi .*+?- , 8-64 caracteres) -
#     ce mot de passe n'a donc jamais pu etre valide.
#   - L'outil officiel wazuh-passwords-tool.sh (embarque dans le paquet,
#     /usr/share/wazuh-indexer/plugins/opensearch-security/tools/) genere
#     bien le nouveau hash localement dans internal_users.yml, mais
#     l'etape qui pousse ce changement vers le cluster EN COURS
#     D'EXECUTION (securityadmin.sh, appele en interne) echoue avec :
#       "Could not find certificate file /etc/wazuh-indexer/certs/admin.pem"
#     Confirme en reel : apres cet echec, le hash local avait change mais
#     l'authentification restait en 401 (le plugin de securite OpenSearch
#     ne relit JAMAIS internal_users.yml au redemarrage sur un cluster
#     deja initialise - meme limite deja documentee dans WAZ_017E pour
#     config.yml).
#   - securityadmin.sh exige un certificat CLIENT (pas le certificat
#     serveur deja copie par WAZ_013A) dont le Subject DN correspond
#     EXACTEMENT a une entree de plugins.security.authcz.admin_dn dans
#     opensearch.yml. Verifie en reel sur le paquet Wazuh 4.14.7 :
#       plugins.security.authcz.admin_dn:
#       - "CN=admin,OU=Wazuh,O=Wazuh,L=California,C=US"
#     Cette valeur est un reglage packageed parmi beaucoup d'autres dans
#     opensearch.yml - meme choix que WAZ_013A : ON NE REECRIT PAS ce
#     fichier, on genere plutot un certificat dont le DN correspond
#     EXACTEMENT a ce que le fichier attend deja.
#
# Ce job genere donc un certificat client "factory_admin" (CN=admin,
# OU=Wazuh, O=Wazuh, L=California, C=US), signe par la MEME CA que le
# reste de l'usine (factory_ca.key/.crt) - le chemin de confiance
# fonctionne automatiquement puisque root-ca.pem (copie par WAZ_013A
# dans /etc/wazuh-indexer/certs/) EST deja cette CA. Ce n'est PAS un
# certificat serveur (pas de SAN, pas de serverAuth) : usage strictement
# client, uniquement presente par securityadmin.sh/wazuh-passwords-tool.sh
# lors d'une reconfiguration de securite locale.
#
# Si PKI_MODE=external (PKI d'entreprise) : ce projet n'a jamais la cle
# privee de la CA cliente (meme principe que PKI_005/007). Exige que
# factory_admin.crt/.key soient deja deposes dans PKI_DIR, deja signes
# par la CA d'entreprise, avec le Subject DN EXACT ci-dessus - erreur
# claire sinon, jamais de generation improvisee.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
cd "${PKI_DIR}"

ADMIN_SUBJ="/C=US/L=California/O=Wazuh/OU=Wazuh/CN=admin"
WAZ_INDXR_USER="${WAZ_INDXR_USER:-wazuh-indexer}"
WAZ_INDXR_CERTS="/etc/wazuh-indexer/certs"

if [ "${PKI_MODE:-generate}" = "external" ]; then
  if [ ! -f "factory_admin.crt" ] || [ ! -f "factory_admin.key" ]; then
    echo "[WAZ_013C] ERREUR : PKI_MODE=external mais ${PKI_DIR}/factory_admin.crt et/ou factory_admin.key sont absents." >&2
    echo "[WAZ_013C] Deposez un certificat client (et sa cle) deja signe par votre CA d'entreprise a cet emplacement," >&2
    echo "[WAZ_013C] avec exactement ce Subject DN (attendu tel quel par opensearch.yml, plugins.security.authcz.admin_dn) :" >&2
    echo "[WAZ_013C]   CN=admin,OU=Wazuh,O=Wazuh,L=California,C=US" >&2
    exit 1
  fi
  echo "[WAZ_013C] PKI_MODE=external : factory_admin.crt/.key deja fournis, generation ignoree."
else
  if [ -f "factory_admin.crt" ] && [ -f "factory_admin.key" ]; then
    echo "[WAZ_013C] factory_admin.crt/.key deja presents, generation ignoree."
  else
    echo "[WAZ_013C] Generation de la cle privee et du certificat client admin (Subject: CN=admin,OU=Wazuh,O=Wazuh,L=California,C=US)..."
    openssl genrsa -out factory_admin.key 2048
    # CORRIGE LE 2026-08-30 (incident reel wef-elk-core, reproduit en
    # reel) : openssl genrsa produit une cle au format PKCS1 traditionnel
    # ("BEGIN RSA PRIVATE KEY"). Le lecteur de cle du plugin de securite
    # OpenSearch (org.opensearch.security.support.PemKeyReader, utilise
    # par securityadmin.sh/wazuh-passwords-tool.sh) n'accepte QUE le
    # format PKCS8 ("BEGIN PRIVATE KEY") - confirme en reel par l'erreur
    # exacte obtenue : "InvalidKeySpecException: Neither RSA, DSA nor EC
    # worked" / "algid parse error, not a sequence". Sans cette
    # conversion, securityadmin.sh echoue systematiquement avant meme de
    # se connecter au cluster, et la securite OpenSearch ne peut jamais
    # etre (re)initialisee - exactement la cause du blocage WAZ_014A
    # observe en reel. Le certificat server (factory_server.key,
    # WAZ_013A) n'est PAS concerne : la couche TLS standard d'OpenSearch
    # accepte le PKCS1 sans probleme (WAZ_014 demarre deja avec succes) -
    # seul le lecteur de cle CLIENT de SecurityAdmin est strict.
    openssl pkcs8 -topk8 -nocrypt -in factory_admin.key -out factory_admin.key.pkcs8
    mv factory_admin.key.pkcs8 factory_admin.key
    openssl req -new -key factory_admin.key -out factory_admin.csr -subj "$ADMIN_SUBJ"
    cat > factory_admin-ext.cnf << CNFEOF
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=clientAuth
CNFEOF
    openssl x509 -req -in factory_admin.csr -CA factory_ca.crt -CAkey factory_ca.key \
      -CAcreateserial -out factory_admin.crt -days "${PKI_DAYS}" -sha256 \
      -extfile factory_admin-ext.cnf
    rm -f factory_admin.csr factory_admin-ext.cnf
  fi
fi

# Verification du Subject DN reellement obtenu (jamais suppose que la
# generation/le depot correspond a ce qui est attendu par opensearch.yml -
# une seule virgule/espace de travers et securityadmin.sh rejettera
# silencieusement l'authentification avec un 401, exactement le symptome
# de depart de cet incident).
REAL_SUBJ=$(openssl x509 -in factory_admin.crt -noout -subject -nameopt RFC2253 2>/dev/null | sed 's/^subject=//')
if [ "$REAL_SUBJ" != "CN=admin,OU=Wazuh,O=Wazuh,L=California,C=US" ]; then
  echo "[WAZ_013C] ERREUR : Subject DN du certificat (${REAL_SUBJ}) ne correspond PAS a l'entree attendue par opensearch.yml (plugins.security.authcz.admin_dn)." >&2
  echo "[WAZ_013C] Attendu exactement : CN=admin,OU=Wazuh,O=Wazuh,L=California,C=US" >&2
  exit 1
fi
echo "[WAZ_013C] Subject DN confirme : ${REAL_SUBJ}"

echo "[WAZ_013C] Copie locale du certificat admin vers ${WAZ_INDXR_CERTS} (noms attendus par securityadmin.sh : admin.pem / admin-key.pem)..."
mkdir -p "$WAZ_INDXR_CERTS"
cp -f "factory_admin.crt" "${WAZ_INDXR_CERTS}/admin.pem"
cp -f "factory_admin.key" "${WAZ_INDXR_CERTS}/admin-key.pem"
chown "${WAZ_INDXR_USER}:${WAZ_INDXR_USER}" "${WAZ_INDXR_CERTS}/admin.pem" "${WAZ_INDXR_CERTS}/admin-key.pem"
chmod 644 "${WAZ_INDXR_CERTS}/admin.pem"
chmod 640 "${WAZ_INDXR_CERTS}/admin-key.pem"

for f in admin.pem admin-key.pem; do
  if [ ! -r "${WAZ_INDXR_CERTS}/$f" ]; then
    echo "[WAZ_013C] ERREUR : ${WAZ_INDXR_CERTS}/$f absent ou illisible apres copie." >&2
    exit 1
  fi
done

echo "[WAZ_013C] OK."
exit 0
