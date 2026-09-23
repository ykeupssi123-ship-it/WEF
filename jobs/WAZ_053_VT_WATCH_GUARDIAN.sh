#!/bin/bash
# WAZ_053_VT_WATCH_GUARDIAN - WEF_WAZ_RUN_VTWATCHGRD
#
# AJOUTE LE 2026-09-18 (demande explicite : "un job sonde devrait
# verifier dans /home/* si un utilisateur a ete cree et l'ajouter au
# job qui a la connaissance des repertoires a surveiller par virus
# total - sinon a quoi sert donc l'orchestration si ce n'est pas pour
# ce genre de choses").
#
# Precision honnete sur l'architecture : orchestrator.sh resout un
# graphe de dependances en PLUSIEURS PASSES pour UNE installation - ce
# n'est jamais une tache de fond continue. Un compte cree APRES le
# dernier passage ne serait jamais revu sans relancer manuellement
# WAZ_050. Le vrai mecanisme deja existant dans ce projet pour ce
# genre de derive continue (jamais couvert par le graphe de
# dependances) est le motif "guardian" : un timer systemd independant,
# deja utilise par jobs/INFRA_004_HEALTH_GUARDIAN.sh - reutilise ici a
# l'identique, jamais reinvente.
#
# Ne touche QUE le bloc FIM (la liste des dossiers) - jamais le bloc
# integration/cle API. Jamais verbeux si rien n'a change (meme
# discipline que INFRA_004) : seul un ecart reel declenche une action
# et un log (journalctl -t wef-vt-watch-guardian).
set -uo pipefail
source "$VARS_FILE"

OSSEC_CONF="/var/ossec/etc/ossec.conf"
[ -f "$OSSEC_CONF" ] || { echo "[WAZ_053_VT_WATCH_GUARDIAN] ERREUR : ${OSSEC_CONF} introuvable." >&2; exit 1; }

WATCH_DIR="${VT_WATCH_DIR:-/root/wef_vt_watch}"
CHECK_SCRIPT="/usr/local/sbin/wef-vt-watch-guardian.sh"
SERVICE_FILE="/etc/systemd/system/wef-vt-watch-guardian.service"
TIMER_FILE="/etc/systemd/system/wef-vt-watch-guardian.timer"

echo "[WAZ_053_VT_WATCH_GUARDIAN] Installation du script de controle ${CHECK_SCRIPT}..."
cat > "$CHECK_SCRIPT" << 'SCRIPTEOF'
#!/bin/bash
# Sonde de derive - genere par jobs/WAZ_053_VT_WATCH_GUARDIAN.sh. Detecte
# un nouveau /home/<utilisateur> (ou point de montage) absent du bloc
# FIM VirusTotal et le rajoute automatiquement, ne redemarre le service
# concerne QUE si un ecart reel est trouve - jamais verbeux sinon
# (tourne en permanence, toutes les 10 minutes).
set -uo pipefail
OSSEC_CONF="__OSSEC_CONF__"
WATCH_DIR="__WATCH_DIR__"
RESTART_SERVICE="__RESTART_SERVICE__"

# CORRIGE LE 2026-09-23 : "/home" (parent, recursif via le FIM realtime
# de Wazuh) remplace l'enumeration individuelle - voir
# WAZ_050_VIRUSTOTAL_INTEGRATION.sh pour le detail complet. Cette sonde
# devient de fait un controle inerte pour ce cas precis (elle calculera
# toujours la meme liste que celle deja posee), conservee par prudence
# plutot que desinstallee.
WATCH_DIRS_LIST=("/root" "/tmp" "$WATCH_DIR" "/home")
for MOUNT_POINT in /media /mnt; do
  mkdir -p "$MOUNT_POINT" 2>/dev/null || true
  WATCH_DIRS_LIST+=("$MOUNT_POINT")
done
NEW_DIRS="$(printf '%s\n' "${WATCH_DIRS_LIST[@]}" | sort -u | paste -sd, -)"

CURRENT_LINE="$(grep -oE '<directories realtime="yes" report_changes="yes">[^<]*</directories>' "$OSSEC_CONF" || true)"
CURRENT_DIRS="$(echo "$CURRENT_LINE" | sed -E 's#^<directories[^>]*>##; s#</directories>$##')"
CURRENT_DIRS_SORTED="$(echo "$CURRENT_DIRS" | tr ',' '\n' | sort -u | paste -sd, -)"

if [ "$NEW_DIRS" = "$CURRENT_DIRS_SORTED" ]; then
  exit 0
fi

logger -t wef-vt-watch-guardian "Ecart detecte sur les dossiers surveilles par VirusTotal - mise a jour : [${CURRENT_DIRS_SORTED:-aucun}] -> [${NEW_DIRS}]"

WAS_IMMUTABLE=0
if lsattr "$OSSEC_CONF" 2>/dev/null | grep -q '^....i'; then
  chattr -i "$OSSEC_CONF"
  WAS_IMMUTABLE=1
fi

sed -i "s|<directories realtime=\"yes\" report_changes=\"yes\">[^<]*</directories>|<directories realtime=\"yes\" report_changes=\"yes\">${NEW_DIRS}</directories>|" "$OSSEC_CONF"

if ! grep -qF "<directories realtime=\"yes\" report_changes=\"yes\">${NEW_DIRS}</directories>" "$OSSEC_CONF"; then
  logger -t wef-vt-watch-guardian "ERREUR : mise a jour du bloc FIM echouee (voir chattr/lsattr)."
  [ "$WAS_IMMUTABLE" -eq 1 ] && chattr +i "$OSSEC_CONF"
  exit 1
fi

if [ "$WAS_IMMUTABLE" -eq 1 ]; then
  chown root:wazuh "$OSSEC_CONF"
  chmod 640 "$OSSEC_CONF"
  chattr +i "$OSSEC_CONF"
fi

systemctl restart "$RESTART_SERVICE"
logger -t wef-vt-watch-guardian "${RESTART_SERVICE} redemarre pour appliquer la nouvelle liste de surveillance."
SCRIPTEOF
sed -i "s|__OSSEC_CONF__|${OSSEC_CONF}|; s|__WATCH_DIR__|${WATCH_DIR}|; s|__RESTART_SERVICE__|wazuh-manager|" "$CHECK_SCRIPT"
chmod 755 "$CHECK_SCRIPT"

echo "[WAZ_053_VT_WATCH_GUARDIAN] Installation du service/timer systemd..."
cat > "$SERVICE_FILE" << 'UNITEOF'
[Unit]
Description=Sonde de derive des dossiers surveilles par VirusTotal (WAZ_053_VT_WATCH_GUARDIAN)

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/wef-vt-watch-guardian.sh
UNITEOF

cat > "$TIMER_FILE" << 'TIMEREOF'
[Unit]
Description=Declenche la sonde de derive VirusTotal toutes les 10 minutes

[Timer]
OnBootSec=90s
OnUnitActiveSec=600s
AccuracySec=10s

[Install]
WantedBy=timers.target
TIMEREOF

systemctl daemon-reload
systemctl enable --now wef-vt-watch-guardian.timer

if ! systemctl is-active wef-vt-watch-guardian.timer >/dev/null 2>&1; then
  echo "[WAZ_053_VT_WATCH_GUARDIAN] ERREUR : wef-vt-watch-guardian.timer n'est pas actif apres activation." >&2
  systemctl status wef-vt-watch-guardian.timer --no-pager >&2 || true
  exit 1
fi

echo "[WAZ_053_VT_WATCH_GUARDIAN] OK (wef-vt-watch-guardian.timer actif, controle toutes les 10 min - voir journalctl -t wef-vt-watch-guardian)."
exit 0
