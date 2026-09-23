#!/bin/bash
# WAG_009_VT_WATCH_DIR - WEF_WAG_RUN_VTWATCHDIR - Surveillance FIM sur VM2
#
# AJOUTE LE 2026-09-17 (demande explicite : "maintenant si la menace
# vient de VM2 ? illustrons"). Jusqu'ici, tous les tests VirusTotal/IOC
# (WAZ_050/WAZ_051) ont ete faits en deposant des fichiers directement
# sur ELK_HOST (VT_WATCH_DIR surveille par le manager lui-meme, agent
# "wef-elk-core", id 000) - jamais depuis un AGENT_HOST reel.
#
# Ce job ouvre le MEME dossier surveille (VT_WATCH_DIR, vars.conf), mais
# cote AGENT (VM2), dans le propre ossec.conf de l'agent - jamais celui
# du manager. Aucune modification cote ELK_HOST n'est necessaire :
# l'integration VirusTotal de WAZ_050 filtre par rule_id (100100,550,
# 553,554), jamais par agent - un evenement FIM remonte par N'IMPORTE
# QUEL agent declenche la meme regle, donc la meme soumission VT,
# automatiquement. Preuve attendue : l'alerte generee portera le nom de
# CET agent (AGENT_NAME, vars.conf) au lieu de "wef-elk-core".
#
# CORRIGE LE 2026-09-18 (incident reel, wef-beats-sensor : "Operation non
# permise" sur ossec.conf au premier vrai test de ce job) : l'hypothese
# initiale ("l'agent n'est jamais verrouille par chattr, WAZ_032 est
# ELK_HOST uniquement") etait une supposition, jamais verifiee sur cette
# VM precise - l'evidence reelle la contredit. Cause exacte non confirmee
# a ce jour (a diagnostiquer : lsattr, ROLE effectif de cette VM,
# historique WAZ_032 sur cette machine) - en attendant, meme motif
# defensif deja etabli ailleurs (WAZ_050/051/052) : deverrouiller si
# immuable, ecrire, TOUJOURS reverrouiller - jamais suppose deja
# correct dans un sens ou dans l'autre.
#
# ELARGI LE 2026-09-18 (demande explicite, meme soir que WAZ_050 :
# "je veux que virustotal detecte seul des fichiers sans qu'un humain
# lui fournisse le fichier" -> "faisons comme vous percevez"). Meme
# logique appliquee ici cote VM2 que cote ELK_HOST (WAZ_050) : jamais
# "/" entier en temps reel (limites inotify + volume de bruit systeme +
# quota API VirusTotal - voir le commentaire detaille dans WAZ_050), mais
# toutes les zones ou un fichier peut legitimement apparaitre sur CETTE
# machine (home reels, /tmp, points de montage USB, le dossier de demo).
set -uo pipefail
source "$VARS_FILE"

WATCH_DIR="${VT_WATCH_DIR:-/root/wef_vt_watch}"
echo "[WAG_009_VT_WATCH_DIR] Preparation du dossier de demo surveille ${WATCH_DIR} sur cet agent..."
mkdir -p "$WATCH_DIR"
chmod 700 "$WATCH_DIR"

OSSEC_CONF="/var/ossec/etc/ossec.conf"
[ -f "$OSSEC_CONF" ] || { echo "[WAG_009_VT_WATCH_DIR] ERREUR : ${OSSEC_CONF} introuvable (WAG_003/WAG_004 doivent avoir tourne)." >&2; exit 1; }

# CORRIGE LE 2026-09-23 (demande explicite, teste en reel avec la
# creation de l'utilisateur "acyrille" sur wef-beats-sensor) : surveiller
# CHAQUE /home/<utilisateur> individuellement (liste figee au moment de
# l'execution) exigeait une sonde de polling (WAG_010, toutes les 10 min)
# pour jamais manquer un compte cree APRES coup. Le FIM Wazuh
# (realtime="yes") est deja RECURSIF par construction : surveiller
# directement le dossier PARENT "/home" couvre automatiquement, sans
# aucun delai, tout nouveau sous-dossier cree dedans (confirme en reel :
# WAG_010 detecte et applique la liste, mais devient desormais un
# controle inerte, jamais plus necessaire pour ce cas precis). Retire
# entierement l'enumeration - un seul "/home" statique suffit.
WATCH_DIRS_LIST=("/root" "/tmp" "$WATCH_DIR" "/home")
for MOUNT_POINT in /media /mnt; do
  mkdir -p "$MOUNT_POINT" 2>/dev/null || true
  WATCH_DIRS_LIST+=("$MOUNT_POINT")
done
FIM_DIRECTORIES="$(printf '%s\n' "${WATCH_DIRS_LIST[@]}" | sort -u | paste -sd, -)"
echo "[WAG_009_VT_WATCH_DIR] Dossiers reellement surveilles sur cet agent (decouverts a l'instant) : ${FIM_DIRECTORIES}"

WAS_IMMUTABLE=0
if lsattr "$OSSEC_CONF" 2>/dev/null | grep -q '^....i'; then
  echo "[WAG_009_VT_WATCH_DIR] ${OSSEC_CONF} est immuable sur cet agent (cause non confirmee - voir commentaire d'en-tete) - deverrouillage temporaire avant reecriture."
  chattr -i "$OSSEC_CONF"
  WAS_IMMUTABLE=1
fi

MARKER="<!-- WEF_AGENT_VT_WATCH_CONFIG (WAG_009, genere automatiquement - ne pas editer a la main) -->"
if grep -qF "$MARKER" "$OSSEC_CONF"; then
  echo "[WAG_009_VT_WATCH_DIR] Bloc deja pose, retrait avant reecriture (evite les doublons a chaque rejeu)..."
  sed -i "\|^${MARKER//\//\\/}\$|,\|^<!-- WEF_AGENT_VT_WATCH_CONFIG_END -->\$|d" "$OSSEC_CONF"
fi

echo "[WAG_009_VT_WATCH_DIR] Ajout de la surveillance FIM temps reel de : ${FIM_DIRECTORIES}..."
{
  echo "$MARKER"
  echo "<ossec_config>"
  echo "  <syscheck>"
  echo "    <directories realtime=\"yes\" report_changes=\"yes\">${FIM_DIRECTORIES}</directories>"
  echo "  </syscheck>"
  echo "</ossec_config>"
  echo "<!-- WEF_AGENT_VT_WATCH_CONFIG_END -->"
} >> "$OSSEC_CONF"
grep -qF "$MARKER" "$OSSEC_CONF" || { echo "[WAG_009_VT_WATCH_DIR] ERREUR : bloc absent apres ecriture (fichier verrouille ? voir chattr/lsattr)." >&2; exit 1; }

if [ "$WAS_IMMUTABLE" -eq 1 ]; then
  echo "[WAG_009_VT_WATCH_DIR] Reverrouillage de ${OSSEC_CONF} (droits + chattr +i)..."
  chown root:wazuh "$OSSEC_CONF"
  chmod 640 "$OSSEC_CONF"
  chattr +i "$OSSEC_CONF"
fi

echo "[WAG_009_VT_WATCH_DIR] Redemarrage de wazuh-agent pour appliquer..."
systemctl restart wazuh-agent

for i in $(seq 1 30); do
  systemctl is-active --quiet wazuh-agent && { echo "[WAG_009_VT_WATCH_DIR] wazuh-agent actif."; echo "[WAG_009_VT_WATCH_DIR] OK. Tout fichier depose dans l'une de ces zones (${FIM_DIRECTORIES}) sur CETTE machine (VM2) - par un humain, un navigateur, une cle USB ou un script - declenche desormais automatiquement une soumission a VirusTotal."; exit 0; }
  sleep 2
done

echo "[WAG_009_VT_WATCH_DIR] ERREUR : wazuh-agent n'a pas redemarre correctement." >&2
journalctl -u wazuh-agent -n 30 --no-pager 2>/dev/null || true
exit 1
