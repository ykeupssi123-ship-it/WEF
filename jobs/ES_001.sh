#!/bin/bash
# ES_001 - WEF_ES_BLD_OSUPDATE - Mise a jour OS Oracle Linux 8.10 (idempotent, mode configurable)
# AJOUTE LE 2026-08-11 (1ere passe) : avant ce correctif, ce job lancait
# dnf clean all + dnf update -y INCONDITIONNELLEMENT, y compris sur une
# machine deja a jour (ex: reextraction de l'archive apres un premier
# passage reussi) - jusqu'a 30-45 min perdues pour rien a chaque fois.
# Meme principe d'idempotence que le reste du projet (rpm -q "$pkg" ||
# dnf install ailleurs) : on verifie d'abord s'il y a vraiment quelque
# chose a faire.
# AJOUTE LE 2026-08-11 (2e passe) : OS_UPDATE_MODE (vars.conf) permet de
# restreindre ou desactiver cette mise a jour si ce serveur heberge
# aussi d'autres services qui ne doivent pas etre impactes par un
# `dnf update -y` global. Voir vars.conf pour le detail des 3 modes.
set -uo pipefail
source "$VARS_FILE"

MODE="${OS_UPDATE_MODE:-full}"
EXCLUDE_ARGS=()
if [ -n "${OS_UPDATE_EXCLUDE_PACKAGES:-}" ]; then
  IFS=',' read -ra _excl_pkgs <<< "$OS_UPDATE_EXCLUDE_PACKAGES"
  for _p in "${_excl_pkgs[@]}"; do
    EXCLUDE_ARGS+=(--exclude="$_p")
  done
fi

if [ "$MODE" = "skip" ]; then
  echo "[ES_001] OS_UPDATE_MODE=skip : mise a jour du systeme desactivee (serveur mutualise avec d'autres services, ou politique geree hors de ce projet). Rien fait - la mise a jour OS reste sous votre responsabilite."
  echo "[ES_001] OK."
  exit 0
fi

if [ "$MODE" = "security" ]; then
  UPDATE_FLAGS=(--security)
  echo "[ES_001] OS_UPDATE_MODE=security : seuls les correctifs de securite seront installes."
else
  UPDATE_FLAGS=()
  [ "$MODE" != "full" ] && echo "[ES_001] AVERTISSEMENT : OS_UPDATE_MODE='${MODE}' non reconnu, traite comme 'full'."
fi

if [ ${#EXCLUDE_ARGS[@]} -gt 0 ]; then
  echo "[ES_001] Paquets exclus de la mise a jour (OS_UPDATE_EXCLUDE_PACKAGES) : ${OS_UPDATE_EXCLUDE_PACKAGES}"
fi

echo "[ES_001] Verification des mises a jour disponibles (dnf check-update)..."
dnf check-update -q "${UPDATE_FLAGS[@]}" "${EXCLUDE_ARGS[@]}" > /dev/null 2>&1
RC=$?
if [ "$RC" -eq 0 ]; then
  echo "[ES_001] Systeme deja a jour (mode ${MODE}), rien a faire."
elif [ "$RC" -eq 100 ]; then
  echo "[ES_001] Mises a jour disponibles, installation (dnf update -y, mode ${MODE})..."
  dnf update -y "${UPDATE_FLAGS[@]}" "${EXCLUDE_ARGS[@]}"
else
  echo "[ES_001] AVERTISSEMENT : dnf check-update a renvoye un code inattendu (${RC}), tentative de mise a jour quand meme par prudence."
  dnf update -y "${UPDATE_FLAGS[@]}" "${EXCLUDE_ARGS[@]}"
fi
echo "[ES_001] OK."
exit 0
