#!/bin/bash
# WAG_012_LEAVE_UNLOCK - WEF_WAG_RUN_LEAVEUNLOCK
#
# AJOUTE LE 2026-09-29, REVU LE 2026-09-30 - retour de conge,
# contrepartie exacte de jobs/WAG_011_LEAVE_LOCK.sh : restaure le mot de
# passe, la cle SSH ET le commentaire de compte (GECOS) d'origine du
# compte designe (LEAVE_USER, vars.conf), leve l'expiration posee en
# filet de securite. Ne touche jamais a la liste CDB cote manager
# (LEAVE_USERS/WAZ_061) - c'est a l'operateur de retirer explicitement
# le nom de LEAVE_USERS dans vars.conf puis de rejouer WAZ_061 sur
# ELK_HOST, exactement comme il l'a explicitement ajoute au depart -
# jamais une desactivation automatique et silencieuse d'une alerte de
# securite.
#
# MANUEL UNIQUEMENT (IN_COND=LEAVE_MANUAL_GATE, jamais satisfaite
# ailleurs - meme gate que WAG_011, ce sont les deux faces d'une meme
# action operateur) :
#   $APP_BIN/order.sh WAG_012_LEAVE_UNLOCK "retour de conge de <utilisateur>"
set -uo pipefail
source "$VARS_FILE"

LEAVE_USER="${LEAVE_USER:-}"
if [ -z "$LEAVE_USER" ]; then
  echo "[WAG_012_LEAVE_UNLOCK] ERREUR : LEAVE_USER est vide dans vars.conf - aucun compte a deverrouiller." >&2
  exit 1
fi
if ! id "$LEAVE_USER" &>/dev/null; then
  echo "[WAG_012_LEAVE_UNLOCK] ERREUR : le compte '${LEAVE_USER}' n'existe pas sur cette machine." >&2
  exit 1
fi

echo "[WAG_012_LEAVE_UNLOCK] Deverrouillage du mot de passe de '${LEAVE_USER}'..."
usermod -U "$LEAVE_USER"

USER_HOME="$(getent passwd "$LEAVE_USER" | cut -d: -f6)"
AUTH_KEYS="${USER_HOME}/.ssh/authorized_keys"
AUTH_KEYS_PARKED="${USER_HOME}/.ssh/authorized_keys.conge"
if [ -f "$AUTH_KEYS_PARKED" ]; then
  echo "[WAG_012_LEAVE_UNLOCK] Restauration de authorized_keys..."
  mv "$AUTH_KEYS_PARKED" "$AUTH_KEYS"
else
  echo "[WAG_012_LEAVE_UNLOCK] Aucune cle mise a l'ecart pour '${LEAVE_USER}' - rien a restaurer de ce cote."
fi

echo "[WAG_012_LEAVE_UNLOCK] Levee de l'expiration de compte (chage -E -1)..."
chage -E -1 "$LEAVE_USER"

GECOS_BACKUP="/etc/wef-leave-gecos-${LEAVE_USER}.bak"
if [ -f "$GECOS_BACKUP" ]; then
  echo "[WAG_012_LEAVE_UNLOCK] Restauration du commentaire de compte (GECOS) d'origine..."
  if ! usermod -c "$(cat "$GECOS_BACKUP")" "$LEAVE_USER"; then
    echo "[WAG_012_LEAVE_UNLOCK] ERREUR : echec de la restauration du commentaire de compte (GECOS) - deverrouillage mot de passe/cle deja effectif." >&2
    exit 1
  fi
  rm -f "$GECOS_BACKUP"
else
  echo "[WAG_012_LEAVE_UNLOCK] Aucune sauvegarde de commentaire trouvee - rien a restaurer de ce cote."
fi

echo "[WAG_012_LEAVE_UNLOCK] OK. '${LEAVE_USER}' peut de nouveau se connecter normalement."
echo "[WAG_012_LEAVE_UNLOCK] Rappel : retirer '${LEAVE_USER}' de LEAVE_USERS (vars.conf) puis rejouer WAZ_061_LEAVE_POLICY sur ELK_HOST pour retirer l'alerte critique associee a ce compte."
exit 0
