#!/bin/bash
# FB_012 - WEF_FB_BLD_OUTGLB - Liaison de sortie vers Logstash
# CORRECTIF 2-VM : pointe vers FACTORY_HOST_IP (VM1), plus 127.0.0.1
# qui ne fonctionnerait pas puisque Logstash tourne sur une autre machine.
#
# SUPPRIME LE 2026-08-31 : FB_009/FB_010 (coffre de secrets Filebeat,
# identifiants FACTORY_INGEST_*) ont ete retires - confirme reel, via
# une reference de configuration Filebeat->Logstash deja PROUVEE en
# production chez l'utilisateur (fichier fourni directement), que
# "output.logstash" ci-dessous n'a JAMAIS besoin d'identifiants ni de
# coffre : le beats input de Logstash n'exige aucune authentification
# cote Filebeat, seul le certificat CA (deja gere ici) est necessaire.
# FB_009/FB_010 armaient un coffre que RIEN, nulle part dans ce fichier
# ni dans jobs_table.csv, ne lisait jamais (aucune reference
# "${factory_ingest_*}" - confirme par recherche exhaustive) : deux
# jobs entierement morts, decouverts en perdant un temps reel
# considerable a les deboguer avant de les identifier comme superflus.
#
# CORRIGE LE 2026-08-31 (meme jour, incident reel : filebeat.service en
# boucle de crash - "Exiting: error unpacking config data: more than
# one namespace configured accessing 'output'") : filebeat.yml livre par
# le paquet contient DEJA un bloc "output.elasticsearch:" ACTIF (pas en
# commentaire - confirme par lecture directe du fichier reel), jamais
# neutralise avant que ce job n'ajoute son propre "output.logstash:" a
# la suite - Filebeat n'accepte qu'UN SEUL namespace "output.*" actif,
# jamais deux. Corrige : le bloc "output.elasticsearch:" (et toutes ses
# lignes indentees) est desormais commente AVANT d'ajouter output.logstash
# - idempotent (une ligne deja commentee ne matche plus le motif de
# detection, aucun risque de double-commentage), fait a CHAQUE passage
# independamment de la detection "output.logstash deja present" plus bas
# (sinon un simple rejeu de ce job, une fois output.logstash deja
# present, aurait laisse le bloc elasticsearch actif a jamais).
set -uo pipefail
source "$VARS_FILE"
[ -n "${FACTORY_HOST_IP:-}" ] || { echo "[FB_012] ERREUR : FACTORY_HOST_IP vide dans vars.conf."; exit 1; }

if grep -q "^output\.elasticsearch:" /etc/filebeat/filebeat.yml 2>/dev/null; then
  echo "[FB_012] Neutralisation du bloc output.elasticsearch actif (paquet par defaut, incompatible avec output.logstash)..."
  awk '
    /^output\.elasticsearch:/ { inblock=1; print "#" $0; next }
    inblock && (/^[[:space:]]/ || /^[[:space:]]*$/) { print "#" $0; next }
    { inblock=0; print }
  ' /etc/filebeat/filebeat.yml > /etc/filebeat/filebeat.yml.wef_tmp && mv /etc/filebeat/filebeat.yml.wef_tmp /etc/filebeat/filebeat.yml
fi

if grep -q "^output.logstash:" /etc/filebeat/filebeat.yml 2>/dev/null; then
  echo "[FB_012] Sortie Logstash deja configuree, ignore."
  echo "[FB_012] OK."
  exit 0
fi
echo "[FB_012] Configuration de la sortie vers Logstash (${FACTORY_HOST_IP}:${LS_BEATS_PORT})..."
cat >> /etc/filebeat/filebeat.yml << YMLEOF
output.logstash:
  hosts: ["${FACTORY_HOST_IP}:${LS_BEATS_PORT}"]
  ssl.certificate_authorities: ["${PKI_DIR}/factory_ca.crt"]
YMLEOF
echo "[FB_012] OK."
exit 0
