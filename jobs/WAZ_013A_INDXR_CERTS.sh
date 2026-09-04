#!/bin/bash
# WAZ_013A - WEF_WAZ_BLD_INDXRCERTS - Raccordement PKI de wazuh-indexer
#
# AJOUTE LE 2026-08-19 (incident reel wef-elk-core, tout premier passage
# reel a WAZ_014 avec les 3 paquets Wazuh vraiment installes) : aucun job
# de la chaine ne copiait jamais les certificats PKI de l'usine vers
# wazuh-indexer, contrairement a Elasticsearch (ES_020), Kibana (KB_014),
# Logstash et les Beats qui ont chacun cette etape. Constate en reel :
# wazuh-indexer.service echouait au demarrage (WAZ_014) avec
# "failed to load plugin class [org.opensearch.security.OpenSearchSecurityPlugin]"
# -> "org.opensearch.OpenSearchException: Unable to read the file
# /etc/wazuh-indexer/certs/root-ca.pem" - dossier confirme absent
# (ls: aucun fichier ou dossier de ce type). Verifie AVANT correctif
# (jamais suppose) : opensearch.yml, tel que fourni par le paquet Wazuh
# 4.14.7, reference deja ces 3 chemins fixes :
#   plugins.security.ssl.http.pemcert_filepath:        certs/indexer.pem
#   plugins.security.ssl.http.pemkey_filepath:          certs/indexer-key.pem
#   plugins.security.ssl.http.pemtrustedcas_filepath:   certs/root-ca.pem
#   (memes 3 noms repetes pour plugins.security.ssl.transport.*)
# Choix delibere : NE PAS reecrire opensearch.yml (contrairement a
# elasticsearch.yml/kibana.yml qui sont entierement sous le controle de
# ce projet ailleurs) - ce fichier packagé contient de nombreux autres
# reglages de securite (cluster, admin_dn, etc.) qu'on ne veut pas
# risquer d'ecraser en le regenerant integralement. A la place : copie
# locale via local_pki_copy (lib/commun.sh, meme reflexe que
# ES_020/KB_014), puis creation de copies renommees aux 3 noms exacts
# deja attendus par le fichier existant - zero ligne d'opensearch.yml
# touchee.
#
# Confirme par l'operateur : id wazuh-indexer -> uid=981(wazuh-indexer)
# gid=981(wazuh-indexer) - proprietaire reel de opensearch.yml sur ce
# serveur (ls -la confirme wazuh-indexer:wazuh-indexer), jamais suppose.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

WAZ_INDXR_USER="${WAZ_INDXR_USER:-wazuh-indexer}"
WAZ_INDXR_CERTS="/etc/wazuh-indexer/certs"

echo "[WAZ_013A] Copie locale des certificats PKI pour wazuh-indexer..."
local_pki_copy "$WAZ_INDXR_CERTS" "${WAZ_INDXR_USER}:${WAZ_INDXR_USER}"

echo "[WAZ_013A] Creation des copies aux noms attendus par opensearch.yml (indexer.pem/indexer-key.pem/root-ca.pem)..."
cp -f "${WAZ_INDXR_CERTS}/factory_ca.crt" "${WAZ_INDXR_CERTS}/root-ca.pem"
cp -f "${WAZ_INDXR_CERTS}/factory_fullchain.pem" "${WAZ_INDXR_CERTS}/indexer.pem"
cp -f "${WAZ_INDXR_CERTS}/factory_server.key" "${WAZ_INDXR_CERTS}/indexer-key.pem"
chown "${WAZ_INDXR_USER}:${WAZ_INDXR_USER}" "${WAZ_INDXR_CERTS}/root-ca.pem" "${WAZ_INDXR_CERTS}/indexer.pem" "${WAZ_INDXR_CERTS}/indexer-key.pem"
chmod 644 "${WAZ_INDXR_CERTS}/root-ca.pem" "${WAZ_INDXR_CERTS}/indexer.pem"
chmod 640 "${WAZ_INDXR_CERTS}/indexer-key.pem"

# Verification explicite, meme discipline que le reste du projet (ex:
# ES_011) : ne jamais supposer qu'une copie/un chown a reussi.
for f in root-ca.pem indexer.pem indexer-key.pem; do
  if [ ! -r "${WAZ_INDXR_CERTS}/$f" ]; then
    echo "[WAZ_013A] ERREUR : ${WAZ_INDXR_CERTS}/$f absent ou illisible apres copie." >&2
    exit 1
  fi
done
echo "[WAZ_013A] OK."
exit 0
