#!/bin/bash
# DNS_003_FIREWALL - WEF_DNS_BLD_FIREWALL - Ouverture du port 53 (DNS)
#
# AJOUTE LE 2026-08-31, ecrit APRES avoir trouve et corrige le meme jour
# un bug reel dans WAZ_005.sh/WAZ_006.sh/ES_013.sh/ES_014.sh/KB_007.sh :
# ces jobs ciblaient des zones firewalld ("internal"/"IngestionZone"/
# "UI_Zone") jamais liees a aucune interface reseau - regles invisibles
# au trafic reel (confirme par `firewall-cmd --get-active-zones` : seule
# "public" est liee a l'interface reelle, ens160). Ce job applique DIRECTEMENT
# la lecon (jamais la meme erreur deux fois le meme jour) : cible "public"
# des l'ecriture, jamais une zone inventee non liee.
set -uo pipefail
source "$VARS_FILE"
echo "[DNS_003] Ouverture du port 53 (tcp+udp, DNS) sur public..."
firewall-cmd --permanent --zone=public --add-port=53/tcp
firewall-cmd --permanent --zone=public --add-port=53/udp
firewall-cmd --reload
echo "[DNS_003] OK."
exit 0
