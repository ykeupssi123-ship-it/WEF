#!/bin/bash
# MNT_purge_rapide_disque.sh - rejoue MNT_006 a MNT_009 : vide le cache
# de flux CVE bruts du Vulnerability Detector (donnees rechargeables,
# sans risque, cause reelle d'un incident disque plein deja rencontre
# sur ce projet). N'affecte AUCUNE alerte ni donnee client.
set -uo pipefail
echo "===================================================================="
echo " MNT_006-009 : PURGE RAPIDE (cache CVE Vulnerability Detector)"
echo "===================================================================="
if [ ! -d /var/ossec ]; then
  echo "Wazuh manager non installe sur cette machine - rien a purger ici."
  exit 0
fi
echo "--- MNT_006 : arret du manager avant de toucher a sa queue ---"
systemctl stop wazuh-manager
echo "--- MNT_007 : purge du cache CVE (rechargeable, pas des alertes) ---"
rm -rf /var/ossec/queue/vd/* /var/ossec/queue/vd_updater/* 2>/dev/null || true
echo "--- MNT_008 : redemarrage du manager (re-telecharge ce qu'il faut) ---"
systemctl start wazuh-manager
sleep 2
systemctl status wazuh-manager --no-pager || true
echo "--- MNT_009 : espace recupere ---"
df -h /
echo "===================================================================="
echo " OK. Si l'espace est toujours insuffisant, le probleme n'est pas"
echo " le cache CVE - relancez MNT_diagnostic.sh pour chercher ailleurs."
echo "===================================================================="
