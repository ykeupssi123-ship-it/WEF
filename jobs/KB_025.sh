#!/bin/bash
# KB_025 - WEF_KB_RUN_EXPORTDASH - Extraction des structures de rendu
#
# CORRECTIF 2026-08-14 (audit systemique) : ce job ne verifiait ni le
# code de sortie de curl, ni le contenu du fichier exporte - un Kibana
# pas encore pret (juste apres le redemarrage de KB_024) ou une erreur
# API aurait pu produire un fichier vide ou un message d'erreur JSON, le
# job se declarant quand meme OK. Corrige : verification du code de
# sortie curl ET que le fichier obtenu n'est ni vide ni une reponse
# d'erreur Kibana (champ "statusCode" typique d'un corps d'erreur).
#
# CORRECTIF 2026-08-19 (incident reel wef-elk-core, decouvert la toute
# premiere fois que la chaine KB_022->KB_025 fonctionnait bout a bout,
# suite aux correctifs KB_013/KB_015/KB_023/KB_024/ES_026 du meme jour) :
# l'appel a l'API Kibana se faisait sans aucune authentification, alors
# que la securite est active depuis le debut du projet - confirme en
# reel : `curl` manuel identique rendait `{"statusCode":401,"error":
# "Unauthorized"}`, jamais un message d'erreur reseau (meme famille que
# l'incident 14 sur ES_061, jamais atteint sur ce point precis de la
# chaine Kibana jusqu'a aujourd'hui). Corrige : authentification via
# l'utilisateur elastic (mot de passe bootstrap, meme identifiant
# superutilisateur deja utilise pour toutes les taches d'administration
# de ce projet - Kibana relaie les identifiants HTTP Basic a
# Elasticsearch pour l'authentification).
set -uo pipefail
source "$VARS_FILE"
BOOTSTRAP_PW_FILE="${STATE_DIR}/es_bootstrap_password.secret"
[ -f "$BOOTSTRAP_PW_FILE" ] || { echo "[KB_025] ERREUR : mot de passe bootstrap introuvable (ES_022 doit avoir tourne)."; exit 1; }
BOOTSTRAP_PW="$(cat "$BOOTSTRAP_PW_FILE")"
OUT_FILE="${STATE_DIR}/kibana_saved_objects_export.ndjson"
echo "[KB_025] Export des Saved Objects..."
if ! curl -sk -f -u "elastic:${BOOTSTRAP_PW}" -H "kbn-xsrf: true" "https://127.0.0.1:${KB_PORT}/api/saved_objects/_export" \
  -H "Content-Type: application/json" -d '{"type":["dashboard","index-pattern","visualization"]}' \
  -o "$OUT_FILE"; then
  echo "[KB_025] ERREUR : l'appel a l'API d'export Kibana a echoue (code HTTP non-2xx ou connexion refusee)." >&2
  exit 1
fi
if [ ! -s "$OUT_FILE" ]; then
  echo "[KB_025] ERREUR : fichier d'export vide ($OUT_FILE)." >&2
  exit 1
fi
if grep -q '"statusCode"' "$OUT_FILE"; then
  echo "[KB_025] ERREUR : reponse d'erreur Kibana dans l'export, voir $OUT_FILE" >&2
  exit 1
fi
echo "[KB_025] OK (export dans ${OUT_FILE})."
exit 0
