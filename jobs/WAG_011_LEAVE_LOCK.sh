#!/bin/bash
# WAG_011_LEAVE_LOCK - WEF_WAG_RUN_LEAVELOCK
#
# AJOUTE LE 2026-09-29, REVU LE 2026-09-30 - moitie "systeme" de
# l'objectif Architecture "Politique de depart en conge" (l'autre
# moitie, la detection cote manager, vit dans
# jobs/WAZ_061_LEAVE_POLICY.sh - ELK_HOST). Verrouille REELLEMENT le
# compte designe (LEAVE_USER, vars.conf) sur AGENT_HOST (VM2) : mot de
# passe verrouille (usermod -L), cle SSH deplacee (jamais supprimee),
# ET commentaire de compte (GECOS) pose explicitement ("En conge depuis
# le ...") - ce commentaire modifie /etc/passwd, deja surveille par le
# FIM, donc le BLOCAGE LUI-MEME devient un evenement visible dans le
# Dashboard, pas seulement la tentative de connexion qui suit.
#
# REVU LE 2026-09-30 (garde-fou EXPLICITE demande - "le systeme doit
# bloquer ça de lui-meme", jamais une simple discipline operateur) :
# ce job REFUSE desormais de verrouiller un compte administrateur.
# Verification en 2 temps, la plus stricte des deux l'emporte :
#   1. Le compte figure dans ADMIN_USERS (vars.conf) ;
#   2. Le compte appartient reellement au groupe wheel OU sudo sur
#      CETTE machine (verification OS, plus autoritaire qu'une simple
#      declaration - couvre le cas d'un admin pas encore ajoute a
#      ADMIN_USERS).
# Si l'une des deux conditions est vraie : ERREUR, exit 1, RIEN n'est
# modifie. Jamais un avertissement ignorable - un job qui echoue est
# visible dans l'audit/l'historique, une politique qui ne repose que sur
# la vigilance de l'operateur ne l'est pas.
#
# MANUEL UNIQUEMENT (IN_COND=LEAVE_MANUAL_GATE, jamais satisfaite
# ailleurs - meme discipline que BEAC_001/WAZ_050) :
#   $APP_BIN/order.sh WAG_011_LEAVE_LOCK "depart en conge de <utilisateur>, retour prevu le <date>"
#
# Idempotent : si les cles/le commentaire sont deja poses (job rejoue
# par erreur), ne les ecrase jamais une seconde fois.
set -uo pipefail
source "$VARS_FILE"

LEAVE_USER="${LEAVE_USER:-}"
if [ -z "$LEAVE_USER" ]; then
  echo "[WAG_011_LEAVE_LOCK] ERREUR : LEAVE_USER est vide dans vars.conf - aucun compte a verrouiller." >&2
  exit 1
fi
if ! id "$LEAVE_USER" &>/dev/null; then
  echo "[WAG_011_LEAVE_LOCK] ERREUR : le compte '${LEAVE_USER}' n'existe pas sur cette machine." >&2
  exit 1
fi

# --- GARDE-FOU : jamais verrouiller un administrateur, verifie par le systeme lui-meme ---
IS_ADMIN=0
IFS=',' read -ra ADMIN_ENTRIES <<< "${ADMIN_USERS:-}"
for entry in "${ADMIN_ENTRIES[@]}"; do
  entry="$(echo "$entry" | xargs)"
  [ "$entry" = "$LEAVE_USER" ] && IS_ADMIN=1
done
if id -nG "$LEAVE_USER" 2>/dev/null | tr ' ' '\n' | grep -qE '^(wheel|sudo)$'; then
  IS_ADMIN=1
fi
if [ "$IS_ADMIN" -eq 1 ]; then
  echo "[WAG_011_LEAVE_LOCK] ERREUR : '${LEAVE_USER}' est un compte ADMINISTRATEUR (present dans ADMIN_USERS et/ou membre de wheel/sudo)." >&2
  echo "[WAG_011_LEAVE_LOCK] Politique : un administrateur n'est jamais verrouille par la procedure de conge - aucune modification effectuee." >&2
  exit 1
fi

echo "[WAG_011_LEAVE_LOCK] Verrouillage du mot de passe de '${LEAVE_USER}'..."
usermod -L "$LEAVE_USER"

USER_HOME="$(getent passwd "$LEAVE_USER" | cut -d: -f6)"
AUTH_KEYS="${USER_HOME}/.ssh/authorized_keys"
AUTH_KEYS_PARKED="${USER_HOME}/.ssh/authorized_keys.conge"
if [ -f "$AUTH_KEYS" ]; then
  echo "[WAG_011_LEAVE_LOCK] Mise a l'ecart de authorized_keys (cle SSH desactivee pour la duree du conge)..."
  mv "$AUTH_KEYS" "$AUTH_KEYS_PARKED"
elif [ -f "$AUTH_KEYS_PARKED" ]; then
  echo "[WAG_011_LEAVE_LOCK] authorized_keys deja mis a l'ecart (job deja joue pour ce conge) - rien a faire de ce cote."
else
  echo "[WAG_011_LEAVE_LOCK] Aucune cle SSH pour '${LEAVE_USER}' - authentification par mot de passe uniquement, deja verrouillee ci-dessus."
fi

GECOS_BACKUP="/etc/wef-leave-gecos-${LEAVE_USER}.bak"
if [ ! -f "$GECOS_BACKUP" ]; then
  ORIGINAL_GECOS="$(getent passwd "$LEAVE_USER" | cut -d: -f5)"
  echo "$ORIGINAL_GECOS" > "$GECOS_BACKUP"
  chmod 600 "$GECOS_BACKUP"
  echo "[WAG_011_LEAVE_LOCK] Pose du commentaire de compte (GECOS) - modification /etc/passwd, deja surveillee par le FIM..."
  usermod -c "EN CONGE depuis le $(date +%Y-%m-%d) - retour prevu: ${LEAVE_END_DATE:-indetermine} - compte verrouille" "$LEAVE_USER"
else
  echo "[WAG_011_LEAVE_LOCK] Commentaire de compte deja pose (job deja joue pour ce conge) - rien a faire de ce cote."
fi

if [ -n "${LEAVE_END_DATE:-}" ]; then
  echo "[WAG_011_LEAVE_LOCK] Date d'expiration du compte fixee au ${LEAVE_END_DATE} (filet de securite - a lever explicitement au retour via WAG_012)."
  chage -E "$LEAVE_END_DATE" "$LEAVE_USER"
fi

echo "[WAG_011_LEAVE_LOCK] OK. '${LEAVE_USER}' est verrouille (mot de passe + cle SSH + commentaire de compte)."
echo "[WAG_011_LEAVE_LOCK] Rappel : pour que toute tentative de connexion sur ce compte declenche une alerte cote Dashboard, LEAVE_USERS doit inclure '${LEAVE_USER}' dans vars.conf puis WAZ_061_LEAVE_POLICY doit avoir ete rejoue sur ELK_HOST."
exit 0
