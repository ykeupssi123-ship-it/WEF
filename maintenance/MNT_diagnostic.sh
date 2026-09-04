#!/bin/bash
# MNT_diagnostic.sh - rejoue MNT_001 a MNT_005 du blueprint (onglet
# MAINTENANCE_MNT) : diagnostic LECTURE SEULE, aucune suppression.
# A lancer en premier des qu'un doute existe sur l'espace disque ou
# juste par prudence avant une nouvelle campagne de deploiement.
set -uo pipefail
echo "===================================================================="
echo " MNT_001-005 : DIAGNOSTIC DISQUE (lecture seule, rien n'est supprime)"
echo "===================================================================="
echo ""
echo "--- MNT_001 : taux de remplissage du systeme de fichiers racine ---"
df -h /
echo ""
echo "--- MNT_002 : repertoires racine les plus volumineux ---"
du -sh /* 2>/dev/null | sort -rh | head -15
echo ""
if [ -d /var ]; then
  echo "--- MNT_003 : sous-repertoires de /var les plus volumineux ---"
  du -sh /var/* 2>/dev/null | sort -rh | head -15
  echo ""
fi
if [ -d /var/ossec ]; then
  echo "--- MNT_004 : sous-repertoires de /var/ossec (manager Wazuh) ---"
  du -sh /var/ossec/* 2>/dev/null | sort -rh | head -15
  echo ""
  echo "--- MNT_005 : cache Vulnerability Detector (coupable connu, ex-incident 17 Go) ---"
  du -sh /var/ossec/queue/* 2>/dev/null | sort -rh | head -15
else
  echo "(Wazuh manager non installe sur cette machine - MNT_004/005 sautes)"
fi
echo ""
echo "===================================================================="
echo " Si /var/ossec/queue/vd ou vd_updater pese plusieurs Go : lancez"
echo " MNT_purge_rapide_disque.sh pour le vider sans rien casser."
echo "===================================================================="
