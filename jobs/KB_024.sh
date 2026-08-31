#!/bin/bash
# KB_024 - WEF_KB_BLD_CABLEFLLBCK - Verification de la liaison locale stricte
#
# CORRECTIF 2026-08-14 (audit systemique suite a l'incident ES_052) :
# ce job appelait "systemctl restart kibana" sans jamais verifier que
# Kibana etait reellement reparti - KB_025 (juste apres, export des
# Saved Objects) aurait echoue silencieusement contre un Kibana pas
# encore pret, sans aucun indice sur la vraie cause. Corrige :
# verification reelle via wait_for_service_active (lib/commun.sh).
#
# CORRECTIF 2026-08-19 (meme audit systemique que KB_023, wef-elk-core) :
# "systemctl is-active" confirme seulement que le PROCESSUS tourne, pas
# que Kibana a reellement reussi a se connecter a Elasticsearch avec les
# identifiants ecrits par KB_023 juste avant - exactement le type d'ecart
# qui a permis a l'incident KB_023 (assistant d'enrolement affiche
# indefiniment) de rester invisible de tous les jobs KB_0xx suivants,
# aucun ne verifiant la connectivite reelle. KB_024 est le point naturel
# pour fermer cet ecart : c'est deja lui qui redemarre Kibana juste apres
# que KB_023 ait ecrit sa configuration/ses identifiants. Ajout d'une
# verification fonctionnelle post-redemarrage sur /api/status
# (".status.overall.level" - format confirme par la documentation
# officielle Kibana 8.x, valeurs possibles : available/degraded/
# unavailable/critical) : le processus ne suffit plus, Kibana doit
# confirmer lui-meme qu'il est reellement "available" avant que ce job
# ne rende la main.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
echo "[KB_024] Levee du blocage et relance de Kibana..."
iptables -D OUTPUT -p tcp --dport ${ES_PORT} -j DROP || true
systemctl restart kibana 2>/dev/null || true
if ! wait_for_service_active kibana 120 5; then
  exit 1
fi
echo "[KB_024] Processus confirme actif (systemctl is-active) - verification de la connectivite reelle a Elasticsearch..."
for i in $(seq 1 60); do
  LEVEL="$(curl -sk "https://127.0.0.1:${KB_PORT}/api/status" 2>/dev/null | python3 -c "
import json, sys
try:
    print(json.load(sys.stdin)['status']['overall']['level'])
except Exception:
    print('indisponible')
" 2>/dev/null)"
  if [ "$LEVEL" = "available" ]; then
    echo "[KB_024] Confirme : status.overall.level = available (connexion Elasticsearch reellement fonctionnelle)."
    echo "[KB_024] OK."
    exit 0
  fi
  sleep 5
done
echo "[KB_024] ERREUR : Kibana est actif au sens systemd mais n'atteint jamais status.overall.level=available (dernier etat observe : '${LEVEL:-indisponible}') - verifier elasticsearch.hosts/elasticsearch.ssl.certificateAuthorities/les identifiants dedies ecrits par KB_023." >&2
exit 1
