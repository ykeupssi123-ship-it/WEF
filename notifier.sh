#!/bin/bash
# notifier.sh - Alerte par email sur echec de job, ajoute le 2026-08-12.
# Le plus gros manque reel face a un centre d'exploitation 24/7 vecu
# sur ce projet : sans ca, un job qui echoue ne fait qu'ecrire un log -
# personne n'est prevenu tant qu'un humain ne va pas le lire.
#
# Utilise curl en SMTP direct (curl --url smtps://...) plutot qu'un
# MTA complet (postfix/sendmail) : rien a installer/configurer comme
# service, une seule commande, coherent avec le reste du projet
# (scripts autonomes plutot que daemons supplementaires).
#
# SECURITE : le mot de passe SMTP n'est JAMAIS dans vars.conf (qui est
# livre dans l'archive de deploiement) - il vit dans un fichier SEPARE
# (SMTP_PASS_FILE, secrets/smtp_password.txt par defaut). Le dossier
# secrets/ EST livre dans l'archive (volontairement vide, voir
# secrets/README_SECRETS.txt) - vous n'avez qu'a y deposer le mot de
# passe (echo ... > secrets/smtp_password.txt && chmod 600 ...), jamais
# le vrai mot de passe lui-meme n'est inclus dans une archive livree.
#
# Usage :
#   ./notifier.sh --test
#     -> envoie un email de test, pour valider la configuration une
#        fois, independamment de tout echec reel.
#   ./notifier.sh <JOB_ID> <JOB_NAME> <RESULTAT> <LOG_FILE>
#     -> appele automatiquement par orchestrator.sh/forcer_job.sh sur
#        un echec. Peut aussi etre appele a la main.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export VARS_FILE="${VARS_FILE:-$HERE/vars.conf}"
source "$VARS_FILE"

# Desactive par defaut : aucune tentative d'envoi tant que ce n'est pas
# explicitement configure (jamais un envoi devine, jamais un echec
# silencieux d'un envoi voue a l'echec).
if [ "${NOTIF_ENABLED:-non}" != "oui" ]; then
  echo "[notifier] NOTIF_ENABLED != oui dans vars.conf - aucune alerte envoyee (normal si non configure)."
  exit 0
fi

MANQUANT=""
[ -z "${SMTP_HOST:-}" ] && MANQUANT="${MANQUANT}SMTP_HOST "
[ -z "${SMTP_USER:-}" ] && MANQUANT="${MANQUANT}SMTP_USER "
[ -z "${SMTP_PASS_FILE:-}" ] && MANQUANT="${MANQUANT}SMTP_PASS_FILE "
[ -z "${NOTIF_FROM:-}" ] && MANQUANT="${MANQUANT}NOTIF_FROM "
[ -z "${NOTIF_TO:-}" ] && MANQUANT="${MANQUANT}NOTIF_TO "
if [ -n "$MANQUANT" ]; then
  echo "[notifier] ERREUR : NOTIF_ENABLED=oui mais variable(s) manquante(s) dans vars.conf : $MANQUANT"
  exit 1
fi
if [ ! -f "$SMTP_PASS_FILE" ]; then
  echo "[notifier] ERREUR : SMTP_PASS_FILE ($SMTP_PASS_FILE) introuvable."
  echo "Creez-le : echo 'mot_de_passe' > $SMTP_PASS_FILE && chmod 600 $SMTP_PASS_FILE"
  exit 1
fi
SMTP_PASS="$(cat "$SMTP_PASS_FILE")"

send_mail(){
  local subject="$1"
  local body="$2"
  local tmp_mail
  tmp_mail=$(mktemp)
  {
    echo "From: ${NOTIF_FROM}"
    echo "To: ${NOTIF_TO}"
    echo "Subject: ${subject}"
    echo "Date: $(date -R)"
    echo "Content-Type: text/plain; charset=UTF-8"
    echo ""
    echo "$body"
  } > "$tmp_mail"

  # Choix du protocole TLS, ajoute le 2026-08-12 (limite trouvee suite
  # a une question legitime : "ce template marche-t-il pour d'autres
  # fournisseurs que OVH ?"). Deux familles existent chez les
  # fournisseurs SMTP, PAS interchangeables :
  #  - TLS IMPLICITE (SMTPS), port 465 typique (OVH Zimbra, Gmail
  #    l'accepte aussi) : la connexion est chiffree DES LE DEBUT.
  #    curl : schema smtps://
  #  - STARTTLS, port 587 typique (Microsoft 365/Outlook, Gmail en
  #    mode recommande, la plupart des relais corporate) : la
  #    connexion demarre EN CLAIR puis bascule en TLS via la commande
  #    STARTTLS. curl : schema smtp:// + --ssl-reqd (exige que le
  #    passage en TLS reussisse, jamais un envoi en clair silencieux).
  # SMTP_TLS_MODE ("ssl" ou "starttls") force le choix si renseigne
  # dans vars.conf ; sinon deduit automatiquement du port (465->ssl,
  # tout le reste->starttls, convention la plus repandue).
  local tls_mode="${SMTP_TLS_MODE:-}"
  if [ -z "$tls_mode" ]; then
    if [ "${SMTP_PORT}" = "465" ]; then tls_mode="ssl"; else tls_mode="starttls"; fi
  fi
  local scheme="smtp"
  [ "$tls_mode" = "ssl" ] && scheme="smtps"

  curl -s -S --url "${scheme}://${SMTP_HOST}:${SMTP_PORT}" \
    --mail-from "${NOTIF_FROM}" \
    --mail-rcpt "${NOTIF_TO}" \
    --user "${SMTP_USER}:${SMTP_PASS}" \
    --upload-file "$tmp_mail" \
    --ssl-reqd
  local rc=$?
  rm -f "$tmp_mail"
  return $rc
}

if [ "${1:-}" = "--test" ]; then
  echo "[notifier] Envoi d'un email de test a ${NOTIF_TO} via ${SMTP_HOST}:${SMTP_PORT}..."
  if send_mail "[WAZ_ELK_FACTORY] Test de notification" \
    "Ceci est un email de test envoye par notifier.sh --test le $(date -Iseconds).
Si vous recevez ceci, la configuration SMTP (vars.conf) est correcte."; then
    echo "[notifier] Email de test envoye avec succes."
    exit 0
  else
    echo "[notifier] ECHEC de l'envoi. Verifiez SMTP_HOST/SMTP_PORT/SMTP_USER/SMTP_PASS_FILE."
    exit 1
  fi
fi

JOB_ID="${1:-}"
JOB_NAME="${2:-}"
RESULTAT="${3:-}"
LOG_FILE="${4:-}"
if [ -z "$JOB_ID" ]; then
  echo "Usage : ./notifier.sh --test"
  echo "        ./notifier.sh <JOB_ID> <JOB_NAME> <RESULTAT> <LOG_FILE>"
  exit 1
fi

MACHINE="$(hostname 2>/dev/null || echo inconnue)"
BODY="Un job a echoue sur ${MACHINE} (${PROJECT_NAME:-WAZ_ELK_FACTORY}, ROLE=${ROLE:-inconnu}).

JOB_ID    : ${JOB_ID}
JOB_NAME  : ${JOB_NAME}
RESULTAT  : ${RESULTAT}
LOG       : ${LOG_FILE}
Date      : $(date -Iseconds)

Consultez :
  ./historique_job.sh ${JOB_ID}
  ./statut_live.sh
  cat ${LOG_FILE}"

echo "[notifier] Envoi de l'alerte pour $JOB_ID..."
if send_mail "[WAZ_ELK_FACTORY] ECHEC : ${JOB_ID} sur ${MACHINE}" "$BODY"; then
  echo "[notifier] Alerte envoyee."
  exit 0
else
  echo "[notifier] ECHEC de l'envoi de l'alerte (mais ne bloque jamais l'orchestrateur)."
  exit 1
fi
