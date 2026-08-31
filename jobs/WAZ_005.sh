#!/bin/bash
# WAZ_005 - WEF_WAZ_BLD_INTRFC - Liaison des fiches d'interconnexion locales
#
# CORRIGE LE 2026-08-31 (incident reel wef-elk-core, decouvert en testant
# les liens https depuis le PC physique de l'utilisateur - 9202 et 5601
# injoignables) : la zone "internal" ciblee ici n'est liee a AUCUNE
# interface reseau (confirme : `firewall-cmd --list-all --zone=internal`
# -> "interfaces:" vide) - un `firewall-cmd --get-active-zones` reel
# montre que ens160 (l'interface reelle de la VM) appartient a la zone
# "public", jamais a "internal". Toute regle ajoutee ici etait donc
# INVISIBLE au trafic reseau reel depuis l'origine de cette usine - les
# ports agents (1514/1515) ne fonctionnaient que par coincidence, deja
# ouverts dans "public" par le propre post-install du paquet RPM
# wazuh-manager (jamais par ce job). Sur une VM neuve sans cette
# coincidence, ce job n'aurait jamais rendu ces ports joignables. Meme
# bug trouve et corrige le meme jour dans WAZ_006.sh/ES_013.sh/
# ES_014.sh/KB_007.sh (toutes zones jamais liees a une interface) -
# corrige partout en ciblant "public", la SEULE zone reellement active
# sur l'interface. Ajout de --reload (absent ici a l'origine) : une
# regle --permanent ne prend effet qu'apres un reload explicite, jamais
# implicite.
set -uo pipefail
source "$VARS_FILE"
echo "[WAZ_005] Ouverture des ports agents (${WAZ_AGENT_PORT}/${WAZ_ENROLL_PORT})..."
firewall-cmd --permanent --zone=public --add-port=${WAZ_AGENT_PORT}/tcp
firewall-cmd --permanent --zone=public --add-port=${WAZ_ENROLL_PORT}/tcp
firewall-cmd --reload
echo "[WAZ_005] OK."
exit 0
