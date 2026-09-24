#!/bin/bash
# LS_008 - WEF_LS_BLD_FWPORTUNVRSL - Ouverture du port de collecte 5044
# CORRECTIF 2-VM : sur une topologie single-host, ce port n'etait ouvert
# qu'aux expediteurs locaux. Avec Filebeat/Metricbeat sur BEATS_HOST_IP
# (VM2), le port doit accepter cette IP precise (pas tout le reseau).
#
# CORRIGE LE 2026-08-31 (incident reel : BEATS_HOST_IP change de
# 192.168.50.129 a 192.168.50.130, l'hote .129 n'etant plus le bon cible)
# - "firewall-cmd --add-source" n'ENLEVE jamais une source deja permanente :
# rejouer ce job apres un changement de BEATS_HOST_IP laissait l'ANCIENNE
# IP autorisee en plus de la nouvelle, silencieusement (meme famille de
# bug "residu jamais nettoye" trouvee et corrigee le meme jour ailleurs
# dans cette usine - LS_024/KB_023/WAZ_023/035/039). Corrige : toute
# source deja permanente dans CollectZone et differente de l'actuelle
# BEATS_HOST_IP est retiree avant d'ajouter la bonne - jamais de confiance
# dans un etat residuel. Ajout de --reload (absent ici a l'origine, meme
# lecon que WAZ_005.sh) : une regle --permanent ne prend jamais effet
# sans reload explicite.
#
# CORRIGE LE 2026-08-31 (meme jour, incident reel decouvert en deployant
# l'agent sur 192.168.50.130 - SSH refuse : "No route to host", alors
# que le ping passait) : "firewall-cmd --get-zone-of-source=192.168.50.
# 130/32" confirme que firewalld fait correspondre une source AVANT une
# interface - TOUT le trafic venant de BEATS_HOST_IP (pas seulement les
# ports beats/syslog) est donc evalue contre CollectZone, jamais contre
# "public", des l'instant ou --add-source est pose plus bas. Or
# CollectZone n'ouvrait jusqu'ici que 514/5044/5514 : SSH (22, necessaire
# a DIST_001 pour rapatrier la CA) et les ports agent Wazuh (1514/1515,
# necessaires a WAG_001+) etaient donc INVISIBLES pour cette meme source
# - un angle mort qui aurait bloque TOUT deploiement d'agent futur des
# le premier contact, jamais revele avant ce jour car aucun agent reel
# n'avait ete deploye jusqu'ici. CollectZone est donc desormais le
# proprietaire unique et complet du jeu de ports necessaires a un
# AGENT_HOST, pas seulement ceux de Logstash - documente ici pour que ce
# ne soit jamais suppose implicite.
set -uo pipefail
source "$VARS_FILE"
echo "[LS_008] Ouverture du port ${LS_BEATS_PORT}/tcp sur CollectZone..."
firewall-cmd --permanent --zone=CollectZone --add-port=${LS_BEATS_PORT}/tcp
echo "[LS_008] Ouverture des ports agent Wazuh (${WAZ_AGENT_PORT}/${WAZ_ENROLL_PORT}) et SSH (22, bootstrap CA DIST_001) sur CollectZone..."
firewall-cmd --permanent --zone=CollectZone --add-port=${WAZ_AGENT_PORT}/tcp
firewall-cmd --permanent --zone=CollectZone --add-port=${WAZ_ENROLL_PORT}/tcp
firewall-cmd --permanent --zone=CollectZone --add-port=22/tcp
# ETENDU LE 2026-09-24 (incident reel, wef-elk-core : port 5044
# injoignable depuis la machine Windows physique de l'operateur, alors
# que 1514/1515 fonctionnaient - le kit Windows, jobs_windows/, n'existait
# pas quand ce job a ete ecrit, aucune IP Windows n'avait jamais ete
# anticipee). BEATS_HOST_IP (une seule IP figee) devient l'ensemble
# BEATS_HOST_IP + BEATS_EXTRA_SOURCES (vars.conf, liste separee par des
# virgules) - MEME discipline de nettoyage deja prouvee necessaire le
# 2026-08-31 (une source permanente jamais retiree automatiquement),
# desormais appliquee a un ENSEMBLE plutot qu'une seule valeur : toute
# source CollectZone deja permanente et absente de cet ensemble est
# retiree, jamais un residu silencieux.
DESIRED_SOURCES=()
[ -n "${BEATS_HOST_IP:-}" ] && DESIRED_SOURCES+=("${BEATS_HOST_IP}/32")
if [ -n "${BEATS_EXTRA_SOURCES:-}" ]; then
  IFS=',' read -ra EXTRA_LIST <<< "$BEATS_EXTRA_SOURCES"
  for IP in "${EXTRA_LIST[@]}"; do
    IP="$(echo "$IP" | xargs)"
    [ -n "$IP" ] && DESIRED_SOURCES+=("${IP}/32")
  done
fi

if [ "${#DESIRED_SOURCES[@]}" -gt 0 ]; then
  echo "[LS_008] Sources CollectZone souhaitees : ${DESIRED_SOURCES[*]}"
  echo "[LS_008] Nettoyage des sources CollectZone perimees (absentes de cet ensemble)..."
  for SRC in $(firewall-cmd --permanent --zone=CollectZone --list-sources 2>/dev/null); do
    KEEP=0
    for WANTED in "${DESIRED_SOURCES[@]}"; do
      [ "$SRC" = "$WANTED" ] && KEEP=1
    done
    if [ "$KEEP" -eq 0 ]; then
      echo "[LS_008]   Retrait de la source perimee ${SRC}..."
      firewall-cmd --permanent --zone=CollectZone --remove-source="$SRC"
    fi
  done
  for WANTED in "${DESIRED_SOURCES[@]}"; do
    echo "[LS_008] Autorisation de la source ${WANTED}..."
    firewall-cmd --permanent --zone=CollectZone --add-source="$WANTED"
  done
else
  echo "[LS_008] ATTENTION : BEATS_HOST_IP et BEATS_EXTRA_SOURCES vides, le port reste ouvert a toute la zone CollectZone."
fi
firewall-cmd --reload
echo "[LS_008] OK."
exit 0
