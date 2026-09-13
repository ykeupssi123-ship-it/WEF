#!/bin/bash
# MNT_reinstall.sh - rejoue MNT_010 a MNT_018 : desinstalle
# COMPLETEMENT une ancienne stack ELK/Wazuh (paquets + repertoires de
# donnees residuels + depot dnf) pour repartir d'une machine vraiment
# vierge. DESTRUCTIF - inventaire affiche et confirmation demandee avant
# toute suppression.
set -uo pipefail
echo "===================================================================="
echo " MNT_010-018 : PURGE COMPLETE (desinstallation totale ELK/Wazuh)"
echo "===================================================================="
echo ""
echo "--- MNT_010 : paquets ELK/Wazuh presents sur cette machine ---"
FOUND_PKG=$(rpm -qa 2>/dev/null | grep -Ei 'wazuh|elastic|logstash|kibana|filebeat|metricbeat|opensearch' || true)
if [ -z "$FOUND_PKG" ]; then
  echo "(aucun paquet trouve)"
else
  echo "$FOUND_PKG"
fi
echo ""
echo "--- MNT_011 : services systemd correspondants ---"
systemctl list-units --type=service --all 2>/dev/null | grep -Ei 'wazuh|elastic|logstash|kibana|filebeat|metricbeat' || echo "(aucun service trouve)"
echo ""

if [ -z "$FOUND_PKG" ] && [ ! -d /var/ossec ] && [ ! -d /etc/wazuh-indexer ] && [ ! -d /etc/elasticsearch ]; then
  echo "===================================================================="
  echo " Rien a purger : cette machine ne porte aucune trace d'une"
  echo " installation ELK/Wazuh anterieure. MNT_010-018 non necessaire."
  echo "===================================================================="
  exit 0
fi

echo "Cette machine porte des traces d'une installation anterieure."
read -r -p "Confirmer la purge COMPLETE et DEFINITIVE (paquets + donnees) ? [oui/NON] " CONFIRM
if [ "$CONFIRM" != "oui" ]; then
  echo "Annule - rien n'a ete supprime."
  exit 1
fi

# CORRIGE LE 2026-09-04 (trouve en preparant une reponse a un incident
# reel etudiant, jamais teste jusqu'ici en conditions reelles) : ce
# script ne purgeait QUE le cote Wazuh (wazuh-indexer/manager/dashboard,
# filebeat) - jamais le cote ELK reel (elasticsearch/logstash/kibana),
# alors meme que MNT_010 (detection, ligne ci-dessus) les cherche deja
# tous les deux. Sur ce projet (WAZ_ELK_FACTORY), ES_017/KB_005/LS_011
# installent bien les paquets reels "elasticsearch"/"kibana"/"logstash"
# (voir PKG_SPEC dans ces jobs) - les laisser en place, avec leurs
# repertoires /etc et /var/lib residuels d'une installation precedente,
# est exactement ce qui a fait echouer ES_021 (WEF_ES_BLD_KSTINIT) chez
# une etudiante : le keystore ou la propriete de /etc/elasticsearch
# restait celle de l'ancienne installation.
#
# CORRIGE LE 2026-09-13 (audit de conformite avant un "repartir de zero"
# demande sur une VM2 AGENT_HOST reelle) : meme angle mort que ci-dessus,
# jamais remarque faute d'un vrai deploiement AGENT_HOST avant cette
# semaine - "metricbeat" et "wazuh-agent" (MB_004.sh/WAG_003.sh) etaient
# absents de toutes les etapes MNT_012-016, alors que MNT_010 les
# cherche deja (grep 'wazuh|elastic|logstash|kibana|filebeat|metricbeat').
# Sur une VM2, un "repartir de zero" incomplet aurait laisse metricbeat/
# wazuh-agent installes, avec un depot metricbeat.repo/filebeat.repo
# residuel - exactement la meme classe d'incident reel que ES_021
# ci-dessus, jamais verifiee jusqu'ici sur ce cote du projet.
echo "--- MNT_012 : arret de tous les services ---"
systemctl stop filebeat metricbeat wazuh-agent wazuh-dashboard wazuh-indexer wazuh-manager kibana logstash elasticsearch 2>/dev/null || true
echo "--- MNT_013 : desactivation du demarrage automatique ---"
systemctl disable filebeat metricbeat wazuh-agent wazuh-dashboard wazuh-indexer wazuh-manager kibana logstash elasticsearch 2>/dev/null || true
echo "--- MNT_014 : desinstallation des paquets ---"
dnf remove -y filebeat metricbeat wazuh-agent wazuh-manager wazuh-indexer wazuh-dashboard kibana logstash elasticsearch 2>/dev/null || true
echo "--- MNT_015 : suppression des repertoires de donnees residuels ---"
rm -rf /var/ossec /etc/filebeat /var/lib/filebeat /var/log/filebeat \
       /etc/metricbeat /var/lib/metricbeat /var/log/metricbeat \
       /etc/wazuh-indexer /var/lib/wazuh-indexer /var/log/wazuh-indexer /usr/share/wazuh-indexer \
       /etc/wazuh-dashboard /var/lib/wazuh-dashboard /var/log/wazuh-dashboard /usr/share/wazuh-dashboard \
       /etc/elasticsearch /var/lib/elasticsearch /var/log/elasticsearch /usr/share/elasticsearch \
       /etc/kibana /var/lib/kibana /var/log/kibana /usr/share/kibana \
       /etc/logstash /var/lib/logstash /var/log/logstash /usr/share/logstash
echo "--- MNT_016 : retrait des depots dnf residuels ---"
rm -f /etc/yum.repos.d/wazuh.repo /etc/yum.repos.d/filebeat.repo /etc/yum.repos.d/metricbeat.repo
dnf clean all
echo "--- MNT_017 : rechargement systemd ---"
systemctl daemon-reload
echo "--- MNT_018 : verification finale ---"
df -h /
REMAINING=$(rpm -qa 2>/dev/null | grep -Ei 'wazuh|filebeat|metricbeat|elasticsearch|kibana|logstash' || true)
if [ -z "$REMAINING" ]; then
  echo "Machine propre confirmee : aucun paquet residuel."
else
  echo "ATTENTION - paquets encore presents : $REMAINING"
fi
echo "===================================================================="
echo " OK. Machine prete pour MNT_019/020 (extraction archive + relance"
echo " orchestrator.sh), ou utilisez directement bin/resume.sh."
echo "===================================================================="
