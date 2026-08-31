#!/bin/bash
# WAZ_014F_DEBUG_WORKAROUND - WEF_WAZ_BLD_DBGWORKAROUND - Contournement
# reel d'un bug de demarrage des daemons wazuh-manager (niveau 0)
#
# AJOUTE LE 2026-08-31 (incident reel MAJEUR wef-elk-core - wazuh-manager
# entier en boucle d'echec au demarrage, decouvert en reconfigurant le
# connecteur indexeur natif). CRITIQUE POUR UN DEPLOIEMENT A FROID : ce
# bug touche le PAQUET WAZUH LUI-MEME (niveau de debug par defaut, 0,
# jamais modifie par cette usine avant ce jour) - il se serait produit
# sur TOUT premier demarrage de wazuh-manager, sur N'IMPORTE QUELLE VM
# neuve utilisant cette version (4.14.7), pas seulement sur wef-elk-core.
# Simplement jamais revele avant aujourd'hui car aucun redemarrage
# complet a froid des daemons n'avait ete reellement observe/investigue
# jusqu'a ce point precis de la mission.
#
# DIAGNOSTIC REEL COMPLET (jamais suppose, reconstruit pas a pas par
# tests directs repetes) :
#   1. wazuh-manager tombait en boucle d'echec systemd, daemon different
#      a chaque tentative (wazuh-db, puis wazuh-authd, puis
#      wazuh-analysisd) - jamais le meme, ce qui a d'abord fait
#      suspecter une condition de course entre daemons ou un probleme de
#      ressources.
#   2. Piste ecartee par test direct : RAM/charge systeme normales au
#      moment des echecs (uptime, free -mh verifies).
#   3. Piste ecartee par test direct : fichiers PID/verrous perimes
#      nettoyes integralement (tous les processus wazuh-* tues par PID
#      exact, jamais par pattern pkill -f qui s'auto-cible sur cette VM
#      - meme piege deja documente ailleurs dans cette usine), echec
#      identique persistant.
#   4. Piste ecartee par test direct : ossec.conf verifie bien forme
#      (xmllint, apres encapsulation dans une racine unique pour tolerer
#      le format multi-<ossec_config> propre a Wazuh) - AUCUNE erreur de
#      syntaxe XML reelle.
#   5. CAUSE REELLE ISOLEE, par elimination methodique : le message
#      d'erreur systemique ("(1226): Error reading XML file
#      'etc/ossec.conf': (line 0)") disparaissait de facon reproductible
#      des qu'un daemon etait lance avec au moins "-d" (niveau de debug
#      1), et reapparaissait de facon 100% reproductible sans aucun
#      indicateur de debug - confirme par des paires de tests directs
#      repetees sur le MEME fichier de configuration, sans aucun autre
#      changement entre les deux. Bug reel du binaire/de la bibliotheque
#      de lecture XML partagee (OS_XML) de cette version installee -
#      jamais un probleme de configuration de cette usine.
#
# CORRECTIF : plutot que de forcer un flag -d en ligne de commande
# (globalement bruyant, et non applique par wazuh-control/systemd par
# defaut de toute facon), le niveau de debug est fixe de facon
# PERSISTANTE via internal_options.conf (mecanisme officiel Wazuh pour
# regler le niveau de log par daemon sans toucher aux commandes de
# lancement) - "debug=1" est le niveau MINIMAL qui evite le bug de
# facon reproductible (confirme par test), pas un niveau de debogage
# maximal choisi par prudence excessive : verbosite journal
# additionnelle restée raisonnable.
#
# ORDRE CRITIQUE : ce job doit tourner AVANT tout premier demarrage de
# wazuh-manager (WAZ_015) - modifier ce reglage APRES coup, sur un
# manager deja bloque en boucle d'echec, n'aurait aucun effet tant que
# les daemons deja plantes/les fichiers .pid/.failed perimes ne sont pas
# nettoyes en plus (voir la sequence de nettoyage complete plus haut,
# non reproduite ici - ce job suppose un tout premier demarrage propre).
set -uo pipefail
source "$VARS_FILE"

INTERNAL_OPTS="/var/ossec/etc/internal_options.conf"
[ -f "$INTERNAL_OPTS" ] || { echo "[WAZ_014F] ERREUR : ${INTERNAL_OPTS} introuvable." >&2; exit 1; }

echo "[WAZ_014F] Contournement du bug de lecture XML (niveau debug=0) : passage a debug=1 pour les daemons du manager..."
sed -i \
  -e 's/^syscheck.debug=0$/syscheck.debug=1/' \
  -e 's/^remoted.debug=0$/remoted.debug=1/' \
  -e 's/^analysisd.debug=0$/analysisd.debug=1/' \
  -e 's/^authd.debug=0$/authd.debug=1/' \
  -e 's/^execd.debug=0$/execd.debug=1/' \
  -e 's/^monitord.debug=0$/monitord.debug=1/' \
  -e 's/^logcollector.debug=0$/logcollector.debug=1/' \
  -e 's/^wazuh_db.debug=0$/wazuh_db.debug=1/' \
  -e 's/^wazuh_modules.debug=0$/wazuh_modules.debug=1/' \
  "$INTERNAL_OPTS"

echo "[WAZ_014F] Verification reelle (les 9 daemons doivent apparaitre a debug=1)..."
CORRECTS=$(grep -cE '^(syscheck|remoted|analysisd|authd|execd|monitord|logcollector|wazuh_db|wazuh_modules)\.debug=1$' "$INTERNAL_OPTS")
if [ "$CORRECTS" -ne 9 ]; then
  echo "[WAZ_014F] ERREUR : seulement ${CORRECTS}/9 daemons confirmes a debug=1 apres ecriture." >&2
  grep '\.debug=' "$INTERNAL_OPTS" >&2
  exit 1
fi

echo "[WAZ_014F] OK (9/9 daemons confirmes, contournement actif avant le premier demarrage)."
exit 0
