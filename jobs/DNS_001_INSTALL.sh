#!/bin/bash
# DNS_001_INSTALL - WEF_DNS_BLD_INSTALL - Installation du serveur DNS interne
#
# AJOUTE LE 2026-08-31 (point #5 de la mission : un FQDN par service pour
# que le PC physique et les futurs agents atteignent chaque tableau de
# bord par son nom, plutot que par IP en dur). dnsmasq choisi plutot que
# bind : deja present sur cette VM (paquet de base OL8, confirme par
# "rpm -q dnsmasq"), configuration minimale pour un usage "un handful de
# FQDN internes + relais vers le DNS habituel pour tout le reste" -
# bind serait disproportionne pour ce besoin.
#
# CORRECTIF 2026-08-19 (meme famille d'incident reel que WAZ_010/WAZ_012,
# meme usine) : "dnf install -y" jamais verifie sans repli IPv4 - meme
# garde-fou applique ici par coherence, meme si dnsmasq/bind-utils se
# sont reveles deja presents sur cette VM au moment ou ce job a ete
# ecrit (paquet de base de l'OS) - sur une VM neuve avec un jeu de
# paquets de base different, l'installation reelle doit rester fiable.
set -uo pipefail
source "$VARS_FILE"

install_if_missing(){
  local pkg="$1"
  if rpm -q "$pkg" &>/dev/null; then
    echo "[DNS_001] ${pkg} deja installe, ignore."
    return 0
  fi
  echo "[DNS_001] Installation de ${pkg}..."
  if ! dnf install -y "$pkg"; then
    echo "[DNS_001] AVERTISSEMENT : dnf install ${pkg} a echoue, nouvel essai en forcant l'IPv4 (cas connu : IPv6 casse sur certains reseaux)..."
    if ! dnf install -y --setopt=ip_resolve=4 "$pkg"; then
      echo "[DNS_001] ERREUR : dnf install ${pkg} a echoue meme en IPv4 force." >&2
      return 1
    fi
  fi
  rpm -q "$pkg" &>/dev/null || { echo "[DNS_001] ERREUR : ${pkg} toujours absent apres dnf install (verification rpm -q)." >&2; return 1; }
}

install_if_missing dnsmasq || exit 1
install_if_missing bind-utils || exit 1
echo "[DNS_001] OK (dnsmasq + bind-utils confirmes installes)."
exit 0
