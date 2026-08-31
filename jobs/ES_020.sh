#!/bin/bash
# ES_020 - WEF_ES_BLD_DIRSECU - Nettoyage/verrouillage du dossier certs local
set -uo pipefail
source "$VARS_FILE"
echo "[ES_020] Reinitialisation de /etc/elasticsearch/certs..."
rm -rf /etc/elasticsearch/certs
mkdir -m 750 /etc/elasticsearch/certs
# Correctif 2026-08-13 : le mkdir seul laisse ce dossier root:root, alors que
# ES_008 avait deja mis tout /etc/elasticsearch a ES_USER:ES_USER. Elasticsearch
# exige que TOUT $ES_PATH_CONF (y compris les sous-dossiers non references dans
# elasticsearch.yml) soit lisible/traversable par l'utilisateur elasticsearch au
# demarrage - sinon AccessDeniedException sur ce dossier au boot du service
# (vu en reel sur ES_026 malgre un PKI_DIR par ailleurs correctement permissionne).
chown "${ES_USER}:${ES_USER}" /etc/elasticsearch/certs

# Correctif 2026-08-14 : incident reel en pre-demo. Le premier correctif
# (chown ci-dessus) a resolu l'AccessDeniedException sur ce dossier, mais
# a revele une deuxieme cause bloquante, differente et plus profonde :
# Elasticsearch 8.19 embarque un systeme de sandboxing interne ("entitlements",
# remplacant du SecurityManager Java retire du JDK) qui INTERDIT par defaut
# la lecture de tout fichier SSL situe hors de /etc/elasticsearch, quels que
# soient les droits Unix - meme un fichier lisible par elasticsearch:elasticsearch
# est refuse (NotEntitledException) si son chemin sort de ce dossier. Le message
# d'erreur ES lui-meme le confirme : "SSL resources should be placed in the
# [/etc/elasticsearch] directory". Or ES_023.sh pointait jusqu'ici directement
# vers PKI_DIR (/etc/pki/factory/certs), un coffre externe partage avec les
# autres composants (Logstash, Kibana, agents) - lecture bloquee au demarrage.
# Solution : copier une fois les 3 fichiers necessaires dans le dossier local
# /etc/elasticsearch/certs (celui prepare ci-dessus), qu'Elasticsearch est
# autorise a lire. PKI_DIR reste la source de verite unique pour tous les
# composants ; cette copie est un simple miroir local propre a Elasticsearch,
# refaite a chaque execution de ce job (idempotent, jamais de derive possible).
echo "[ES_020] Copie locale des certificats PKI (entitlements ES 8.19)..."
cp -f "${PKI_DIR}/factory_server.key" "${PKI_DIR}/factory_fullchain.pem" "${PKI_DIR}/factory_ca.crt" /etc/elasticsearch/certs/
chown "${ES_USER}:${ES_USER}" /etc/elasticsearch/certs/factory_server.key /etc/elasticsearch/certs/factory_fullchain.pem /etc/elasticsearch/certs/factory_ca.crt
chmod 640 /etc/elasticsearch/certs/factory_server.key
chmod 644 /etc/elasticsearch/certs/factory_fullchain.pem /etc/elasticsearch/certs/factory_ca.crt
echo "[ES_020] OK."
exit 0
