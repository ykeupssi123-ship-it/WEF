#!/bin/bash
# ES_052 - WEF_ES_RUN_SYSDRCVR - Verification relance apres sinistre
#
# CORRECTIF 2026-08-14 (incident reel pre-demo, VM1) : ce job appelait
# juste "systemctl start elasticsearch" et se declarait OK des que la
# commande rendait la main - sans jamais verifier qu'Elasticsearch
# etait reellement reparti. Le pkill -9 d'ES_051 (juste avant, meme
# chaine) met un instant a etre constate par systemd (transition vers
# l'etat "failed" pas instantanee) : le "systemctl start" d'ES_052,
# lance dans la meme seconde, arrivait parfois PENDANT cette fenetre,
# ou systemd croyait encore l'unite active - il ne faisait alors rien
# et rendait quand meme un code de sortie 0 (confirme par
# journalctl : aucune nouvelle ligne "Starting Elasticsearch..." apres
# le crash). Consequence reelle observee : ES_052 -> OK alors
# qu'Elasticsearch etait reste "failed" pendant 8+ minutes, et ES_053
# (poll de sante, 5 min max) tournait a vide sans aucun indice sur la
# vraie cause. Meme famille de bug que ES_027/le mot de passe elastic
# (un job ne doit jamais assumer qu'une action a fonctionne - il doit
# le verifier). Corrige : verification reelle via wait_for_service_active
# (lib/commun.sh) - point unique desormais, voir ce fichier pour le
# detail de la logique (audit du meme jour ayant trouve 5 autres jobs
# avec le meme risque : ES_055, KB_024, WAZ_028, WAZ_035, WAZ_039).
# Une pause de 2s avant la premiere lecture d'etat supprime en plus la
# fenetre de course elle-meme, plutot que de compter uniquement sur le
# polling pour la rattraper.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
echo "[ES_052] Redemarrage d'Elasticsearch..."

# Pause volontaire avant la premiere lecture d'etat : laisse a systemd le
# temps de traiter le SIGKILL d'ES_051 et de faire basculer l'unite vers
# "failed" AVANT qu'on interroge/agisse - supprime la fenetre de course a
# la racine plutot que d'esperer la rattraper seulement par du polling.
sleep 2

if wait_for_service_active elasticsearch 120 5; then
  echo "[ES_052] Confirme actif (systemctl is-active)."
  echo "[ES_052] OK."
  exit 0
fi
exit 1
