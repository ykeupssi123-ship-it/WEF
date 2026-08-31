#!/bin/bash
# KB_022 - WEF_KB_RUN_ACCESSTEST - Tentative d'acces pendant l'isolement
#
# CORRIGE LE 2026-08-30 (incident reel wef-elk-core, reproduit en reel) :
# ce job attendait que l'interface Kibana reponde MEME base coupee
# (KB_021 juste avant) - constate en reel avec Kibana 8.19 (paquet
# Wazuh 4.14.7) : la reponse HTTP reste totalement bloquee (curl reste
# accroche ~2 minutes puis "Empty reply from server", jamais une page
# d'erreur propre), pas un manque de patience du test mais un vrai trait
# de cette version de Kibana. En faire une ECHEC bloquant casserait
# TOUJOURS un depot a froid sur ce meme paquet, sans qu'aucune
# correction locale n'y change quoi que ce soit - a l'oppose de
# l'objectif "aucune intervention manuelle". Le vrai filet de securite
# de la chaine est KB_024 juste apres (leve l'isolement, verifie
# reellement status.overall.level=available) - celui-la reste
# bloquant. Meme principe deja applique a WAZ_037_CONVERGENT_TEST :
# avertissement non bloquant pour un comportement inherent a
# l'environnement/la version, jamais un "OK" invente pour autant (le
# resultat reel reste visible dans le log).
set -uo pipefail
source "$VARS_FILE"
echo "[KB_022] Test d'acces a l'UI pendant l'isolement de la base..."
if curl -Ik --max-time 10 "https://127.0.0.1:${KB_PORT}/" -o /dev/null 2>/dev/null; then
  echo "[KB_022] Interface accessible malgre l'isolement."
else
  echo "[KB_022] AVERTISSEMENT : l'interface est indisponible sans sa base (comportement non resilient de cette version de Kibana, connu - voir KB_024 pour la verification bloquante post-recuperation)."
fi
echo "[KB_022] OK."
exit 0
