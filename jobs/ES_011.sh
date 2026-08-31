#!/bin/bash
# ES_011 - WEF_ES_BLD_FWARMING - Activation permanente du pare-feu local
set -uo pipefail
source "$VARS_FILE"
echo "[ES_011] Activation de firewalld..."
systemctl enable --now firewalld

# Correctif 2026-08-14 (incident reel pre-demo) : activer firewalld pour
# la premiere fois sur une machine impose d'un coup les regles de la
# zone par defaut. Si SSH n'y est pas deja explicitement autorise, la
# consequence est un verrouillage total de l'acces a distance (WinSCP et
# toute nouvelle session SSH refusees) - vecu en reel sur VM1. On ne
# suppose jamais que la zone par defaut de l'image a garde SSH ; on le
# garantit nous-memes, sur la zone reellement active (jamais "public" en
# dur, au cas ou l'image aurait une autre zone par defaut).
ACTIVE_ZONE="$(firewall-cmd --get-default-zone)"
echo "[ES_011] Garantie explicite : SSH reste autorise sur la zone ${ACTIVE_ZONE}..."
firewall-cmd --permanent --zone="${ACTIVE_ZONE}" --add-service=ssh

# Correctif 2026-08-14 (durcissement) : AllowZoneDrifting est un reglage
# heritage de firewalld, signale par firewalld lui-meme comme "considered
# an insecure configuration option" au demarrage. Desactive explicitement
# plutot que de laisser la valeur par defaut de l'image.
if [ -f /etc/firewalld/firewalld.conf ]; then
  sed -i 's/^AllowZoneDrifting=.*/AllowZoneDrifting=no/' /etc/firewalld/firewalld.conf
fi

firewall-cmd --reload

# Verification 2026-08-14 (durcissement) : ne jamais se contenter de
# supposer qu'une commande a produit l'effet voulu - vecu en reel le
# meme jour, une commande firewall-cmd --add-service=ssh executee a la
# main a echoue silencieusement ("FirewallD is not running") sans que
# l'operateur s'en rende compte immediatement. On verifie ici que ssh
# est REELLEMENT present dans la zone active, et on echoue bruyamment
# (arret de l'orchestrateur) si ce n'est pas le cas - plutot que de
# continuer et decouvrir la coupure d'acces distant plus tard.
if ! firewall-cmd --zone="${ACTIVE_ZONE}" --list-services | grep -qw ssh; then
  echo "[ES_011] ERREUR : ssh n'apparait PAS dans la zone ${ACTIVE_ZONE} malgre la commande d'ajout. Acces distant potentiellement compromis - ne pas continuer sans verifier a la main (firewall-cmd --zone=${ACTIVE_ZONE} --list-services)."
  exit 1
fi
echo "[ES_011] Verifie : ssh est bien autorise sur la zone ${ACTIVE_ZONE}."
echo "[ES_011] OK."
exit 0
