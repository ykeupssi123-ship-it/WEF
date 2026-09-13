#!/bin/bash
# INFRA_008_NTP_CLIENT - WEF_INFRA_BLD_NTPCLI - Client NTP (VM2/AGENT_HOST)
#
# Voir jobs/INFRA_007_NTP_SERVER.sh pour le contexte complet de
# l'incident reel ayant motive ce job (ecart d'horloge VM1/VM2 d'environ
# 1h, cause du "rien ne s'affiche dans Kibana" malgre des documents deja
# indexes). VM2 se synchronise UNIQUEMENT sur VM1 (FACTORY_HOST_IP),
# jamais sur un pool externe directement - meme principe de source
# unique de verite que tout le reste de cette usine (PKI, Logstash...).
#
# Force une correction IMMEDIATE de l'horloge (chronyc makestep) plutot
# que de laisser chronyd corriger progressivement par petits ajustements
# (comportement par defaut, bien trop lent pour un ecart d'1h avant une
# demo) - sans jamais casser un futur reglage system plus strict : cette
# correction ponctuelle au demarrage du service n'empeche pas chronyd de
# revenir a un ajustement progressif ensuite pour le suivi continu.
set -uo pipefail
source "$VARS_FILE"

install_if_missing(){
  local pkg="$1"
  if rpm -q "$pkg" &>/dev/null; then
    echo "[INFRA_008_NTP_CLIENT] ${pkg} deja installe, ignore."
    return 0
  fi
  echo "[INFRA_008_NTP_CLIENT] Installation de ${pkg}..."
  if ! dnf install -y "$pkg"; then
    echo "[INFRA_008_NTP_CLIENT] AVERTISSEMENT : dnf install ${pkg} a echoue, nouvel essai en forcant l'IPv4..."
    dnf install -y --setopt=ip_resolve=4 "$pkg" || { echo "[INFRA_008_NTP_CLIENT] ERREUR : dnf install ${pkg} a echoue meme en IPv4 force." >&2; return 1; }
  fi
  rpm -q "$pkg" &>/dev/null || { echo "[INFRA_008_NTP_CLIENT] ERREUR : ${pkg} toujours absent apres dnf install." >&2; return 1; }
}
install_if_missing chrony || exit 1

CONFIG_FILE="/etc/chrony.conf"
[ -f "$CONFIG_FILE" ] || { echo "[INFRA_008_NTP_CLIENT] ERREUR : ${CONFIG_FILE} introuvable (paquet chrony corrompu ?)." >&2; exit 1; }

MARKER="# WEF_NTP_CLIENT_CONFIG (INFRA_008, genere automatiquement - ne pas editer a la main)"
if grep -qF "$MARKER" "$CONFIG_FILE"; then
  echo "[INFRA_008_NTP_CLIENT] Bloc de configuration deja pose, retrait avant reecriture (evite les doublons a chaque rejeu)..."
  sed -i "/^${MARKER//\//\\/}\$/,/^# WEF_NTP_CLIENT_CONFIG_END\$/d" "$CONFIG_FILE"
fi

echo "[INFRA_008_NTP_CLIENT] Neutralisation des sources NTP par defaut du paquet (commentees, jamais supprimees)..."
sed -i -E 's/^[[:space:]]*(server|pool)[[:space:]]+/# &/' "$CONFIG_FILE"

{
  echo "$MARKER"
  echo "server ${FACTORY_HOST_IP} iburst"
  echo "makestep 1.0 3"
  echo "# WEF_NTP_CLIENT_CONFIG_END"
} >> "$CONFIG_FILE"

echo "[INFRA_008_NTP_CLIENT] Desactivation de systemd-timesyncd (evite un conflit avec chronyd)..."
timedatectl set-ntp false 2>/dev/null || true

systemctl enable chronyd
systemctl restart chronyd

echo "[INFRA_008_NTP_CLIENT] Heure avant correction : $(date -u)"
sleep 3
echo "[INFRA_008_NTP_CLIENT] Forçage d'une correction immediate (chronyc makestep)..."
chronyc makestep || echo "[INFRA_008_NTP_CLIENT] AVERTISSEMENT : makestep a echoue (VM1 pas encore joignable ? chronyd la reessaiera seul en tache de fond)."
sleep 2
echo "[INFRA_008_NTP_CLIENT] Heure apres correction : $(date -u)"

echo "[INFRA_008_NTP_CLIENT] Etat des sources NTP :"
chronyc sources -v || true
echo "[INFRA_008_NTP_CLIENT] Etat du suivi :"
chronyc tracking || true

systemctl is-active --quiet chronyd || { echo "[INFRA_008_NTP_CLIENT] ERREUR : chronyd n'est pas actif apres redemarrage." >&2; exit 1; }
echo "[INFRA_008_NTP_CLIENT] OK (chronyd actif, synchronise sur ${FACTORY_HOST_IP})."
exit 0
