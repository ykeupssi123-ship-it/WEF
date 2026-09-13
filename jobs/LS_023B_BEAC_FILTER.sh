#!/bin/bash
# LS_023B_BEAC_FILTER - WEF_LS_RUN_BEACFILTER - Filtre scenario metier BEAC
#
# AJOUTE LE 2026-09-13 (scenario metier BEAC - LCB-FT/CyrielleMoney).
# Reconnait les evenements provenant des 2 fichiers de log simules
# (ecrits par WAZ_049D_SEED_LCBFT_LIVE / WAZ_049F_SEED_CYRIELLEMONEY_LIVE
# sur AGENT_HOST, expedies ici par Filebeat comme n'importe quel autre
# log de l'hote, FB_007/FB_012 - AUCUNE config Filebeat dediee : ces 2
# fichiers vivent directement sous /var/log/, deja couverts par le
# prospecteur generique "/var/log/*.log") : les reconnait par leur champ
# ECS "[log][file][path]" (ajoute par Filebeat lui-meme a chaque
# evenement, jamais invente ici), parse le JSON qu'ils contiennent
# (Filebeat livre chaque ligne brute dans "message", jamais parsee), et
# laisse LS_024.sh les router vers leur index dedie par CE MEME champ de
# chemin - une seule source de verite pour "d'ou vient cet evenement",
# jamais un champ synthetique ajoute ici en plus.
set -uo pipefail
source "$VARS_FILE"
echo "[LS_023B_BEAC_FILTER] Ecriture du filtre scenario BEAC..."
mkdir -p /etc/logstash/conf.d
FILTER_FILE="/etc/logstash/conf.d/12-beac-filter.conf"
if [ -e "$FILTER_FILE" ] && lsattr "$FILTER_FILE" 2>/dev/null | grep -q '^....i'; then
  echo "[LS_023B_BEAC_FILTER] ${FILTER_FILE} est immuable (deja verrouille par LS_036_FINAL) - deverrouillage temporaire avant reecriture."
  chattr -i "$FILTER_FILE"
fi
cat > "$FILTER_FILE" << CONFEOF
filter {
  if [log][file][path] =~ "lcbft_detections\.log\$" or [log][file][path] =~ "cyriellemoney_transfers\.log\$" {
    json {
      source => "message"
    }
  }
}
CONFEOF
if ! grep -q 'lcbft_detections' "$FILTER_FILE" 2>/dev/null; then
  echo "[LS_023B_BEAC_FILTER] ERREUR : ${FILTER_FILE} ne contient pas le filtre attendu apres ecriture - la redirection a echoue silencieusement (fichier toujours immuable ?)." >&2
  lsattr "$FILTER_FILE" >&2 2>/dev/null || true
  exit 1
fi
echo "[LS_023B_BEAC_FILTER] OK."
exit 0
