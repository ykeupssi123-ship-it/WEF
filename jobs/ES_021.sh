#!/bin/bash
# ES_021 - WEF_ES_BLD_KSTINIT - Initialisation du keystore local
#
# CORRECTIF 2026-08-14 (audit systemique suite a l'incident LS_B025_ARMED) :
# "elasticsearch-keystore create" se declarait OK sans jamais verifier
# que le fichier avait reellement ete cree - meme famille de bug qui a
# fait planter Logstash en boucle sur VM1 (voir README, incident 17).
# Corrige : on verifie que le fichier existe reellement apres l'appel.
set -uo pipefail
source "$VARS_FILE"
if [ -f /etc/elasticsearch/elasticsearch.keystore ]; then
  echo "[ES_021] Keystore deja initialise, ignore."
  echo "[ES_021] OK."
  exit 0
fi
# CORRIGE le 2026-09-01 (echec reel rapporte par une etudiante deployant
# depuis GitHub, reproductible a l'identique sur 2 tentatives successives -
# voir docs/JOURNAL_TECHNIQUE.md) : deux defauts reels cumules.
#
# 1) "elasticsearch-keystore create" tournait en root, jamais documente
# comme methode officielle par Elastic - la doc Elastic elle-meme
# recommande "sudo -u elasticsearch ... elasticsearch-keystore create".
# Root PEUT creer le fichier (les droits Unix ne bloquent jamais root),
# mais le processus keystore lui-meme verifie parfois la coherence entre
# l'utilisateur courant et le proprietaire de ES_PATH_CONF avant d'ecrire,
# et refuse dans certains cas plutot que de creer un fichier root:root
# incoherent avec le reste de /etc/elasticsearch (deja ES_USER:ES_USER
# depuis ES_008/ES_020). Execute desormais comme ES_USER, coherent avec
# le proprietaire reel du dossier.
#
# 2) La sortie reelle de la commande (stdout/stderr) n'etait jamais
# capturee ni affichee en cas d'echec - le job se contentait de verifier
# l'ABSENCE du fichier, sans jamais montrer le message d'erreur exact
# qui aurait explique pourquoi. Corrige : sortie complete capturee et
# affichee sur l'echec, pour que le PROCHAIN echec (meme sur une machine
# jamais vue) soit diagnosticable sans deviner.
echo "[ES_021] Creation du keystore Elasticsearch (utilisateur ${ES_USER})..."
KEYSTORE_OUT="$(sudo -u "${ES_USER}" /usr/share/elasticsearch/bin/elasticsearch-keystore create < /dev/null 2>&1)"
KEYSTORE_RC=$?
echo "$KEYSTORE_OUT"
if [ $KEYSTORE_RC -ne 0 ]; then
  echo "[ES_021] ERREUR : 'elasticsearch-keystore create' a rendu le code ${KEYSTORE_RC}. Sortie ci-dessus." >&2
  exit 1
fi
if [ ! -f /etc/elasticsearch/elasticsearch.keystore ]; then
  echo "[ES_021] ERREUR : /etc/elasticsearch/elasticsearch.keystore n'existe toujours pas apres 'elasticsearch-keystore create' (code sortie ${KEYSTORE_RC}, aucune erreur rapportee mais fichier absent - verifier manuellement les droits de /etc/elasticsearch)." >&2
  exit 1
fi
echo "[ES_021] OK (fichier confirme present)."
exit 0
