#!/bin/bash
# WAZ_018_NET - WEF_WAZ_RUN_CRASHTESTNET - Rupture reseau sortante (crash test)
set -uo pipefail
source "$VARS_FILE"
echo "[WAZ_018_NET] Coupure des flux sortants (hors boucle locale)..."

# Filet de securite (dead man's switch), ajoute le 2026-08-14 suite a
# l'audit systemique post-incident firewalld/ES_011 du meme jour. Ce
# test coupe TOUT le trafic sortant, y compris SSH - normalement leve
# par WAZ_021_RECOVER.sh apres WAZ_019_FLOOD et WAZ_020_VERIFY. Mais si
# la chaine s'interrompt entre les deux (crash de l'orchestrateur,
# kill -9, erreur operateur), la machine reste injoignable sauf console
# locale - meme classe de risque que l'incident reel ES_011 vecu ce
# jour. Un processus detache, independant de l'orchestrateur, leve la
# coupure automatiquement apres un delai fixe meme si tout le reste
# s'arrete - WAZ_021_RECOVER.sh reste le chemin normal (immediat), ce
# filet n'est qu'un rattrapage si ce chemin normal n'a pas eu lieu.
NET_TEST_TIMEOUT_SEC="${WAZ_NET_TEST_TIMEOUT_SEC:-300}"
nohup bash -c "sleep ${NET_TEST_TIMEOUT_SEC}; iptables -F OUTPUT" > /dev/null 2>&1 &
disown

iptables -A OUTPUT -d 0.0.0.0/0 ! -o lo -j DROP
echo "[WAZ_018_NET] OK (filet de securite arme : retour automatique dans ${NET_TEST_TIMEOUT_SEC}s si WAZ_021_RECOVER n'a pas encore tourne d'ici la)."
exit 0
