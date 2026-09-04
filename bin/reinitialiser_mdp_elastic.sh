#!/bin/bash
# reinitialiser_mdp_elastic.sh - SEUL point sanctionne pour reinitialiser
# le mot de passe du compte superutilisateur 'elastic'. Ajoute le
# 2026-08-14 suite a un incident reel pre-demo : le mot de passe stocke
# dans state/es_bootstrap_password.secret avait diverge du mot de passe
# reellement actif dans le cluster (le dossier de donnees Elasticsearch
# avait survecu d'une tentative de deploiement anterieure sur la meme
# machine - bootstrap.password dans le keystore n'est lu qu'a la toute
# premiere creation de l'index de securite, il ne sert plus a rien sur
# un cluster deja initialise). Decouvert tardivement au job ES_028 avec
# une simple erreur 401, sans lien evident avec sa vraie cause.
#
# Avant ce script, la reparation exigeait une sequence de commandes
# tapees a la main (elasticsearch-reset-password, puis recopier la
# valeur dans le bon fichier, avec les bons droits) - source d'erreur
# reelle, et rien de reproductible a documenter pour un client. Desormais
# une seule commande, un seul fichier modifie (state/es_bootstrap_password.secret,
# qui reste LA reference unique - rien d'autre a synchroniser a la main),
# et une verification immediate (jamais suppose que la reinitialisation a
# fonctionne).
#
# Usage :
#   ./reinitialiser_mdp_elastic.sh              -> interactif, detaille chaque etape
#   ./reinitialiser_mdp_elastic.sh --silencieux  -> pour appel automatique
#                                                    (voir jobs/lib/es_admin_curl.sh,
#                                                    qui invoque ce script tout seul
#                                                    des qu'une desynchronisation
#                                                    est detectee)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export VARS_FILE="${VARS_FILE:-$HERE/vars.conf}"
source "$VARS_FILE"

SILENCIEUX="${1:-}"
PWFILE="${STATE_DIR}/es_bootstrap_password.secret"
ES_RESET_BIN="/usr/share/elasticsearch/bin/elasticsearch-reset-password"

log(){ [ "$SILENCIEUX" = "--silencieux" ] || echo "$1"; }

if [ ! -x "$ES_RESET_BIN" ]; then
  echo "[reinitialiser_mdp_elastic] ERREUR : $ES_RESET_BIN introuvable - Elasticsearch est-il installe sur cette machine ?" >&2
  exit 1
fi

log "[reinitialiser_mdp_elastic] Reinitialisation du mot de passe 'elastic' aupres du cluster..."
NOUVEAU_MDP="$("$ES_RESET_BIN" -u elastic -s -b)"
if [ -z "$NOUVEAU_MDP" ]; then
  echo "[reinitialiser_mdp_elastic] ERREUR : elasticsearch-reset-password n'a renvoye aucune valeur." >&2
  exit 1
fi

mkdir -p "${STATE_DIR}"
printf '%s' "$NOUVEAU_MDP" > "$PWFILE"
chmod 600 "$PWFILE"
log "[reinitialiser_mdp_elastic] Nouvelle valeur ecrite dans ${PWFILE} (reference unique - rien d'autre a modifier)."

log "[reinitialiser_mdp_elastic] Verification (jamais suppose que la reinitialisation a fonctionne)..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --cacert "${PKI_DIR}/factory_ca.crt" -u "elastic:${NOUVEAU_MDP}" "https://127.0.0.1:${ES_PORT}/_cluster/health")
if [ "$HTTP_CODE" != "200" ]; then
  echo "[reinitialiser_mdp_elastic] ERREUR : verification post-reinitialisation en echec (HTTP ${HTTP_CODE}). Intervention manuelle requise." >&2
  exit 1
fi

log "[reinitialiser_mdp_elastic] Verifie : authentification OK (HTTP 200)."
log "[reinitialiser_mdp_elastic] OK."
exit 0
