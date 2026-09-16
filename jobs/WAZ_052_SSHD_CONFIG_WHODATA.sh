#!/bin/bash
# WAZ_052_SSHD_CONFIG_WHODATA - WEF_WAZ_RUN_SSHDWHODATA
#
# AJOUTE LE 2026-09-16 (demande explicite : "modifions le fichier de
# config du SSH... je veux qu'on dise qu'on a modifie ce fichier et par
# qui"). Surveille /etc/ssh/sshd_config avec FIM en mode "whodata" - pas
# seulement "qu'est-ce qui a change" (mode realtime standard, deja
# utilise pour VT_WATCH_DIR), mais "QUI l'a change" (utilisateur reel,
# PID, processus responsable) - necessite le sous-systeme audit Linux
# (auditd), que Wazuh pilote lui-meme pour ce fichier precis une fois
# whodata active (pas besoin de regle audit manuelle, contrairement a
# WAG_008_AUDITD_INTEGRATION qui, elle, audite les EXECUTIONS de
# commandes - usage different, meme paquet).
#
# Fichier unique surveille (jamais tout /etc/ssh/) - portee volontairement
# etroite, exactement ce qui a ete demande.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

install_if_missing(){
  local pkg="$1"
  if rpm -q "$pkg" &>/dev/null; then
    echo "[WAZ_052_SSHD_CONFIG_WHODATA] ${pkg} deja installe, ignore."
    return 0
  fi
  echo "[WAZ_052_SSHD_CONFIG_WHODATA] Installation de ${pkg}..."
  if ! dnf install -y "$pkg"; then
    echo "[WAZ_052_SSHD_CONFIG_WHODATA] AVERTISSEMENT : dnf install ${pkg} a echoue, nouvel essai en forcant l'IPv4..."
    dnf install -y --setopt=ip_resolve=4 "$pkg" || { echo "[WAZ_052_SSHD_CONFIG_WHODATA] ERREUR : dnf install ${pkg} a echoue meme en IPv4 force." >&2; return 1; }
  fi
  rpm -q "$pkg" &>/dev/null || { echo "[WAZ_052_SSHD_CONFIG_WHODATA] ERREUR : ${pkg} toujours absent apres dnf install." >&2; return 1; }
}
install_if_missing audit || exit 1
# CORRIGE LE 2026-09-16 (incident reel, wef-elk-core) : "systemctl
# restart auditd" est refuse par systemd sur cet OS ("Operation refused,
# unit auditd.service may be requested by dependency only... configured
# to refuse manual start/stop") - protection deliberee du sous-systeme
# d'audit contre un redemarrage manuel accidentel. Sans consequence si
# le service est deja actif (cas le plus frequent) - jamais force dans
# ce cas, uniquement demarre s'il ne l'etait pas deja.
systemctl enable auditd 2>/dev/null || true
if systemctl is-active --quiet auditd; then
  echo "[WAZ_052_SSHD_CONFIG_WHODATA] auditd deja actif, pas de redemarrage force (evite le refus systemd connu sur ce service)."
else
  systemctl start auditd || true
fi
for i in $(seq 1 30); do
  systemctl is-active --quiet auditd && break
  sleep 2
done
systemctl is-active --quiet auditd || { echo "[WAZ_052_SSHD_CONFIG_WHODATA] ERREUR : auditd n'a pas demarre (requis pour le mode whodata)." >&2; exit 1; }

SSHD_CONFIG="/etc/ssh/sshd_config"
[ -f "$SSHD_CONFIG" ] || { echo "[WAZ_052_SSHD_CONFIG_WHODATA] ERREUR : ${SSHD_CONFIG} introuvable." >&2; exit 1; }

OSSEC_CONF="/var/ossec/etc/ossec.conf"
[ -f "$OSSEC_CONF" ] || { echo "[WAZ_052_SSHD_CONFIG_WHODATA] ERREUR : ${OSSEC_CONF} introuvable." >&2; exit 1; }

# Meme motif deja etabli (WAZ_050/051, meme soir) : deverrouiller si
# immuable (WAZ_032), reecrire, toujours reverrouiller.
if lsattr "$OSSEC_CONF" 2>/dev/null | grep -q '^....i'; then
  echo "[WAZ_052_SSHD_CONFIG_WHODATA] ${OSSEC_CONF} est immuable (deja verrouille par WAZ_032) - deverrouillage temporaire avant reecriture."
  chattr -i "$OSSEC_CONF"
fi

MARKER="<!-- WEF_SSHD_WHODATA_CONFIG (WAZ_052, genere automatiquement - ne pas editer a la main) -->"
if grep -qF "$MARKER" "$OSSEC_CONF"; then
  echo "[WAZ_052_SSHD_CONFIG_WHODATA] Bloc deja pose, retrait avant reecriture..."
  sed -i "\|^${MARKER//\//\\/}\$|,\|^<!-- WEF_SSHD_WHODATA_CONFIG_END -->\$|d" "$OSSEC_CONF"
fi
echo "[WAZ_052_SSHD_CONFIG_WHODATA] Ajout de la surveillance whodata de ${SSHD_CONFIG}..."
{
  echo "$MARKER"
  echo "<ossec_config>"
  echo "  <syscheck>"
  echo "    <directories whodata=\"yes\" check_all=\"yes\">${SSHD_CONFIG}</directories>"
  echo "  </syscheck>"
  echo "</ossec_config>"
  echo "<!-- WEF_SSHD_WHODATA_CONFIG_END -->"
} >> "$OSSEC_CONF"
grep -qF "$MARKER" "$OSSEC_CONF" || { echo "[WAZ_052_SSHD_CONFIG_WHODATA] ERREUR : bloc absent apres ecriture (fichier verrouille ? voir chattr/lsattr)." >&2; exit 1; }

echo "[WAZ_052_SSHD_CONFIG_WHODATA] Reverrouillage de ${OSSEC_CONF} (droits + chattr +i)..."
chown root:wazuh "$OSSEC_CONF"
chmod 640 "$OSSEC_CONF"
chattr +i "$OSSEC_CONF"

echo "[WAZ_052_SSHD_CONFIG_WHODATA] Redemarrage de wazuh-manager pour appliquer..."
systemctl restart wazuh-manager
if ! wait_for_service_active wazuh-manager 180 5; then
  echo "[WAZ_052_SSHD_CONFIG_WHODATA] ERREUR : wazuh-manager n'a pas redemarre." >&2
  journalctl -u wazuh-manager -n 30 --no-pager 2>/dev/null || true
  exit 1
fi

echo "[WAZ_052_SSHD_CONFIG_WHODATA] OK. Toute modification de ${SSHD_CONFIG} declenchera desormais une alerte FIM avec l'auteur reel (utilisateur/PID/processus)."
exit 0
