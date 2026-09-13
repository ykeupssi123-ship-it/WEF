#!/bin/bash
# INFRA_007_NTP_SERVER - WEF_INFRA_BLD_NTPSRV - Serveur NTP local (VM1)
#
# AJOUTE LE 2026-09-14, suite a un incident reel : `date -u` sur les 2
# VMs a montre un ecart d'environ 1h (VM1 22:59:37, VM2 23:59:56), cause
# du "rien ne s'affiche dans Kibana" malgre des documents deja indexes -
# le champ @timestamp d'un evenement Filebeat est fixe par l'HORLOGE DE
# LA MACHINE QUI ECRIT LE LOG (VM2), pas par Logstash sur VM1 : un ecart
# d'horloge entre les 2 VMs place silencieusement les evenements hors de
# la fenetre de temps affichee par defaut dans Discover.
#
# Adapte d'un script reel utilise sur une mission precedente de
# l'operateur (chrony + couplage a un serveur NTP) - jamais copie tel
# quel : les serveurs NTP internes d'entreprise (IPs privees) n'ont pas
# de sens ici, remplaces par le modele deja etabli dans cette usine
# entiere : VM1 (ELK_HOST) est la source unique de verite, VM2 (et tout
# futur AGENT_HOST) s'y synchronise - jamais l'inverse (voir
# INFRA_008_NTP_CLIENT.sh). VM1 tente en plus de se caler sur l'heure
# reelle via NTP_UPSTREAM_POOL (vars.conf, public) si le lab a un acces
# internet ; sinon "local stratum 10" lui permet de continuer a servir
# une heure coherente a VM2 meme sans source externe - l'objectif reel
# n'est pas une precision atomique, juste que toutes les VMs de cette
# usine soient d'accord entre elles.
#
# Le sed de l'original (lignes centos.pool.ntp.org litterales) etait deja
# inadapte a Oracle Linux (bloc vendor different) - remplace ici par une
# commande generique qui commente TOUTE ligne "server "/"pool " deja
# presente, quelle que soit sa formulation exacte, jamais une liste de
# motifs fige a un OS precis.
set -uo pipefail
source "$VARS_FILE"

install_if_missing(){
  local pkg="$1"
  if rpm -q "$pkg" &>/dev/null; then
    echo "[INFRA_007_NTP_SERVER] ${pkg} deja installe, ignore."
    return 0
  fi
  echo "[INFRA_007_NTP_SERVER] Installation de ${pkg}..."
  if ! dnf install -y "$pkg"; then
    echo "[INFRA_007_NTP_SERVER] AVERTISSEMENT : dnf install ${pkg} a echoue, nouvel essai en forcant l'IPv4..."
    dnf install -y --setopt=ip_resolve=4 "$pkg" || { echo "[INFRA_007_NTP_SERVER] ERREUR : dnf install ${pkg} a echoue meme en IPv4 force." >&2; return 1; }
  fi
  rpm -q "$pkg" &>/dev/null || { echo "[INFRA_007_NTP_SERVER] ERREUR : ${pkg} toujours absent apres dnf install." >&2; return 1; }
}
install_if_missing chrony || exit 1

CONFIG_FILE="/etc/chrony.conf"
[ -f "$CONFIG_FILE" ] || { echo "[INFRA_007_NTP_SERVER] ERREUR : ${CONFIG_FILE} introuvable (paquet chrony corrompu ?)." >&2; exit 1; }

MARKER="# WEF_NTP_SERVER_CONFIG (INFRA_007, genere automatiquement - ne pas editer a la main)"
if grep -qF "$MARKER" "$CONFIG_FILE"; then
  echo "[INFRA_007_NTP_SERVER] Bloc de configuration deja pose, retrait avant reecriture (evite les doublons a chaque rejeu)..."
  sed -i "/^${MARKER//\//\\/}\$/,/^# WEF_NTP_SERVER_CONFIG_END\$/d" "$CONFIG_FILE"
fi

echo "[INFRA_007_NTP_SERVER] Neutralisation des sources NTP par defaut du paquet (commentees, jamais supprimees)..."
sed -i -E 's/^[[:space:]]*(server|pool)[[:space:]]+/# &/' "$CONFIG_FILE"

{
  echo "$MARKER"
  if [ -n "${NTP_UPSTREAM_POOL:-}" ]; then
    echo "pool ${NTP_UPSTREAM_POOL} iburst"
  fi
  echo "# VM2 (BEATS_HOST_IP) et tout futur AGENT_HOST peuvent interroger cette VM :"
  echo "allow ${BEATS_HOST_IP}/32"
  echo "# Sert quand meme une heure coherente a VM2 si aucune source externe n'est joignable (lab isole) :"
  echo "local stratum 10"
  echo "# WEF_NTP_SERVER_CONFIG_END"
} >> "$CONFIG_FILE"

echo "[INFRA_007_NTP_SERVER] Ouverture du port NTP (123/udp) sur CollectZone..."
firewall-cmd --permanent --zone=CollectZone --add-port=123/udp
firewall-cmd --reload

echo "[INFRA_007_NTP_SERVER] Desactivation de systemd-timesyncd (evite un conflit avec chronyd)..."
timedatectl set-ntp false 2>/dev/null || true

systemctl enable chronyd
systemctl restart chronyd
sleep 2

echo "[INFRA_007_NTP_SERVER] Etat des sources NTP :"
chronyc sources -v || true
echo "[INFRA_007_NTP_SERVER] Etat du suivi :"
chronyc tracking || true

systemctl is-active --quiet chronyd || { echo "[INFRA_007_NTP_SERVER] ERREUR : chronyd n'est pas actif apres redemarrage." >&2; exit 1; }
echo "[INFRA_007_NTP_SERVER] OK (chronyd actif, port 123/udp ouvert a ${BEATS_HOST_IP} sur CollectZone)."
exit 0
