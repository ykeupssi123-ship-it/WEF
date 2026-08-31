#!/bin/bash
# DNS_004_START - WEF_DNS_RUN_STARTVERIFY - Demarrage et verification reelle
# de la resolution DNS interne
#
# AJOUTE LE 2026-08-31. Classe RUN, pas BUILD (voir point #8 de la
# mission, classification a venir) : ce job ne construit rien de
# nouveau, il ARME un service deja construit par DNS_001/002/003 et
# VERIFIE un comportement fonctionnel (la resolution reelle), exactement
# la meme distinction que WAZ_020_VERIFY vis-a-vis de WAZ_014B.
#
# CORRECTIF (discipline deja appliquee partout ailleurs dans cette
# usine, ex. WAZ_015/WAZ_016/WAZ_035/WAZ_039) : jamais "systemctl
# restart" seul pris comme preuve de succes - wait_for_service_active
# (lib/commun.sh) exige en plus une confirmation de stabilite (voir son
# propre en-tete pour l'incident reel qui a motive cette exigence). Et
# jamais un service "actif" pris comme preuve qu'il repond correctement
# : une resolution DNS reelle est testee ci-dessous pour CHAQUE FQDN
# declare par DNS_002_ZONE.sh, avec le verdict exact (adresse obtenue)
# affiche - jamais un simple "ca devrait marcher".
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

DOMAIN="${DNS_DOMAIN:-wef.local}"

echo "[DNS_004] Demarrage de dnsmasq..."
systemctl enable dnsmasq 2>/dev/null || true
systemctl restart dnsmasq 2>/dev/null || true
if ! wait_for_service_active dnsmasq 60 5; then
  echo "[DNS_004] ERREUR : dnsmasq.service n'a pas pu etre confirme actif et stable." >&2
  journalctl -u dnsmasq -n 30 --no-pager 2>/dev/null || true
  exit 1
fi

echo "[DNS_004] Verification reelle de la resolution (dig @${FACTORY_HOST_IP})..."
ECHEC=0
for FQDN in dashboard kibana indexer api elk-core; do
  RESOLU="$(dig +short "@${FACTORY_HOST_IP}" "${FQDN}.${DOMAIN}" A 2>/dev/null | tail -n 1)"
  if [ "$RESOLU" = "$FACTORY_HOST_IP" ]; then
    echo "[DNS_004]   ${FQDN}.${DOMAIN} -> ${RESOLU} (OK)"
  else
    echo "[DNS_004]   ${FQDN}.${DOMAIN} -> '${RESOLU:-aucune reponse}' (ATTENDU : ${FACTORY_HOST_IP}) - ECHEC" >&2
    ECHEC=1
  fi
done

if [ "$ECHEC" -ne 0 ]; then
  echo "[DNS_004] ERREUR : au moins un FQDN ne resout pas correctement (voir ci-dessus)." >&2
  exit 1
fi

echo "[DNS_004] OK (les 5 FQDN de service resolvent reellement vers ${FACTORY_HOST_IP})."
exit 0
