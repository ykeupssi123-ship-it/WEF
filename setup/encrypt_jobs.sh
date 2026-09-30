#!/bin/bash
# setup/encrypt_jobs.sh - AJOUTE LE 2026-09-30, demande explicite :
# empecher qui que ce soit (l'etudiante, un visiteur du depot GitHub une
# fois public, etc.) de lire le CONTENU des scripts de job, sans jamais
# empecher leur EXECUTION reelle par l'orchestrateur.
#
# USAGE RESERVE A L'OPERATEUR (vous), JAMAIS a executer sur une machine
# a laquelle l'etudiante a un acces autonome :
#   sudo setup/encrypt_jobs.sh
#
# CE QUE CE SCRIPT FAIT :
#   1. Genere UNE FOIS secrets/jobs_encryption_key.txt (256 bits
#      aleatoires, openssl rand) si absent - jamais regenere ensuite
#      (le regenerer rendrait tout jobs.enc/ existant illisible).
#   2. Chiffre (AES-256-CBC, PBKDF2, 100000 iterations - openssl
#      standard, jamais un chiffrement invente ici) CHAQUE fichier .sh
#      sous jobs/ (y compris jobs/lib/) vers son equivalent sous
#      jobs.enc/, avec l'extension .enc - jamais l'inverse, ce script ne
#      touche JAMAIS aux fichiers source dans jobs/.
#
# CE QUE CA PROTEGE REELEMENT, ET CE QUE CA NE PROTEGE PAS (honnete) :
#   - Protege : la lecture CASUELLE du code (cat/less/nano/un depot
#     GitHub rendu public, un clone du depot sans la cle) - sans
#     secrets/jobs_encryption_key.txt, jobs.enc/*.enc n'est qu'un bloc
#     binaire illisible.
#   - Ne protege PAS : un operateur qui a deja acces root a la machine
#     ET au moment ou lib/run_job.sh dechiffre temporairement le script
#     pour l'executer (fenetre volontairement la plus courte possible,
#     voir lib/run_job.sh) - aucun chiffrement ne peut empecher root de
#     lire ce que root execute lui-meme. Ce n'est PAS un DRM, c'est un
#     controle d'acces au CODE SOURCE pour un usage normal (execution
#     via order.sh/orchestrator.sh/scheduler.sh), jamais presente comme
#     davantage.
#
# DEPLOIEMENT REEL (pour que la protection serve a quelque chose) :
# distribuez jobs.enc/ + secrets/jobs_encryption_key.txt (ce dernier
# HORS du depot git, transmis separement, a la main, seulement quand
# vous autorisez une execution) - JAMAIS le dossier jobs/ en clair sur
# une machine a laquelle l'etudiante a un acces autonome. Tant que
# jobs/ en clair reste present a cote de jobs.enc/, rien n'est protege
# (lib/run_job.sh continue de preferer jobs.enc/ des qu'il existe, mais
# jobs/ resterait lisible directement par un simple cat).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY_FILE="${JOBS_ENCRYPTION_KEY_FILE:-$HERE/secrets/jobs_encryption_key.txt}"
JOBS_DIR="$HERE/jobs"
ENC_DIR="$HERE/jobs.enc"

if [ ! -f "$KEY_FILE" ]; then
  echo "[encrypt_jobs] Generation de la cle de chiffrement (${KEY_FILE})..."
  mkdir -p "$(dirname "$KEY_FILE")"
  openssl rand -base64 32 > "$KEY_FILE"
  chmod 600 "$KEY_FILE"
  echo "[encrypt_jobs] Cle generee. CONSERVEZ-LA EN LIEU SUR, HORS DU DEPOT GIT (deja dans .gitignore via secrets/*)."
  echo "[encrypt_jobs] Sans cette cle, jobs.enc/ est definitivement illisible - aucune recuperation possible en cas de perte."
else
  echo "[encrypt_jobs] Cle existante reutilisee (${KEY_FILE}) - jamais regeneree automatiquement."
fi

if [ ! -d "$JOBS_DIR" ]; then
  echo "[encrypt_jobs] ERREUR : ${JOBS_DIR} introuvable." >&2
  exit 1
fi

COUNT=0
while IFS= read -r -d '' plain_file; do
  rel_path="${plain_file#"$JOBS_DIR"/}"
  enc_file="$ENC_DIR/${rel_path}.enc"
  mkdir -p "$(dirname "$enc_file")"
  openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -salt -pass "file:$KEY_FILE" -in "$plain_file" -out "$enc_file"
  chmod 644 "$enc_file"
  COUNT=$((COUNT+1))
done < <(find "$JOBS_DIR" -type f -name '*.sh' -print0)

echo "[encrypt_jobs] OK. ${COUNT} script(s) chiffre(s) sous ${ENC_DIR}."
echo "[encrypt_jobs] Rappel : jobs/ en clair est toujours present a cote - voir l'en-tete de ce script pour le deploiement reel qui protege effectivement le code."
exit 0
