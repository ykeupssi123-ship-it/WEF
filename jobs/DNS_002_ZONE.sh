#!/bin/bash
# DNS_002_ZONE - WEF_DNS_BLD_ZONE - Declaration de la zone interne (un FQDN par service)
#
# AJOUTE LE 2026-08-31 (point #5 de la mission). Fichier dedie sous
# /etc/dnsmasq.d/ (jamais /etc/dnsmasq.conf lui-meme, deja configure par
# le paquet pour charger ce repertoire - "conf-dir=/etc/dnsmasq.d" -
# confirme par lecture directe du fichier livre par le paquet) - meme
# philosophie que /etc/logstash/conf.d (LS_024) : un fichier proprement
# a nous, jamais une edition in-place d'un fichier possede par le
# paquet. Regenere ENTIEREMENT a chaque passage (meme principe que
# LS_024/WAZ_017C/KB_023, tous corriges le meme jour pour la meme raison
# ailleurs dans cette usine) : jamais de residu d'un FQDN retire de
# vars.conf, jamais de doublon si ce job est rejoue.
#
# PORTEE VOLONTAIREMENT MINIMALE : ce serveur ne fait PAS autorite sur
# tout un domaine - il ne repond que pour les quelques FQDN de service
# listes ci-dessous (tous -> FACTORY_HOST_IP, un seul hote pour l'instant)
# et RELAIE toute autre requete vers le resolveur habituel de la VM
# (comportement par defaut de dnsmasq, jamais desactive ici via
# "no-resolv") - un poste qui utilise ce DNS en secondaire (cas du PC
# physique de l'utilisateur) garde donc une resolution Internet normale,
# il gagne seulement la resolution de ces FQDN internes en plus.
set -uo pipefail
source "$VARS_FILE"

ZONE_FILE="/etc/dnsmasq.d/wef-zone.conf"
DOMAIN="${DNS_DOMAIN:-wef.local}"

echo "[DNS_002] Ecriture de la zone ${DOMAIN} (${ZONE_FILE})..."
cat > "$ZONE_FILE" << CONFEOF
# Regenere entierement par DNS_002_ZONE.sh - ne pas editer a la main.
listen-address=127.0.0.1,${FACTORY_HOST_IP}
bind-interfaces
domain=${DOMAIN}
expand-hosts

# Un FQDN par service (WEF_DNS_BLD_ZONE) - tous sur ${FACTORY_HOST_IP}
# aujourd'hui (un seul hote ELK_HOST) ; a eclater vers plusieurs IP le
# jour ou un service demenage sur sa propre machine.
address=/dashboard.${DOMAIN}/${FACTORY_HOST_IP}
address=/kibana.${DOMAIN}/${FACTORY_HOST_IP}
address=/indexer.${DOMAIN}/${FACTORY_HOST_IP}
address=/api.${DOMAIN}/${FACTORY_HOST_IP}
address=/elk-core.${DOMAIN}/${FACTORY_HOST_IP}
CONFEOF
chmod 644 "$ZONE_FILE"

if ! dnsmasq --test --conf-file=/etc/dnsmasq.conf 2>&1 | grep -q "syntax check OK"; then
  echo "[DNS_002] ERREUR : dnsmasq rejette la configuration apres ecriture de ${ZONE_FILE} (dnsmasq --test) :" >&2
  dnsmasq --test --conf-file=/etc/dnsmasq.conf >&2 2>&1 || true
  exit 1
fi

echo "[DNS_002] OK (zone ${DOMAIN} : dashboard/kibana/indexer/api/elk-core -> ${FACTORY_HOST_IP})."
exit 0
