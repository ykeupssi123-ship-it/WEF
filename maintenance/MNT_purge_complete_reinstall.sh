#!/bin/bash
# MNT_purge_complete_reinstall.sh - rejoue MNT_010 a MNT_018 : desinstalle
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

if [ -z "$FOUND_PKG" ] && [ ! -d /var/ossec ] && [ ! -d /etc/wazuh-indexer ]; then
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

echo "--- MNT_012 : arret de tous les services ---"
systemctl stop filebeat wazuh-dashboard wazuh-indexer wazuh-manager 2>/dev/null || true
echo "--- MNT_013 : desactivation du demarrage automatique ---"
systemctl disable filebeat wazuh-dashboard wazuh-indexer wazuh-manager 2>/dev/null || true
echo "--- MNT_014 : desinstallation des paquets ---"
dnf remove -y filebeat wazuh-manager wazuh-indexer wazuh-dashboard 2>/dev/null || true
echo "--- MNT_015 : suppression des repertoires de donnees residuels ---"
rm -rf /var/ossec /etc/filebeat /var/lib/filebeat /var/log/filebeat \
       /etc/wazuh-indexer /var/lib/wazuh-indexer /var/log/wazuh-indexer /usr/share/wazuh-indexer \
       /etc/wazuh-dashboard /var/lib/wazuh-dashboard /var/log/wazuh-dashboard /usr/share/wazuh-dashboard
echo "--- MNT_016 : retrait du depot dnf Wazuh ---"
rm -f /etc/yum.repos.d/wazuh.repo
dnf clean all
echo "--- MNT_017 : rechargement systemd ---"
systemctl daemon-reload
echo "--- MNT_018 : verification finale ---"
df -h /
REMAINING=$(rpm -qa 2>/dev/null | grep -Ei 'wazuh|filebeat' || true)
if [ -z "$REMAINING" ]; then
  echo "Machine propre confirmee : aucun paquet residuel."
else
  echo "ATTENTION - paquets encore presents : $REMAINING"
fi
echo "===================================================================="
echo " OK. Machine prete pour MNT_019/020 (extraction archive + relance"
echo " orchestrator.sh), ou utilisez directement bin/reprise_deploiement.sh."
echo "===================================================================="
