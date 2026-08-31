#!/bin/bash
# INFRA_005_DISK_HYGIENE - WEF_INFRA_BLD_DISKHYG - Nettoyage reel et
# permanent de l'espace disque non lie a l'usine
#
# AJOUTE LE 2026-08-31 (incident reel wef-elk-core, constate en direct
# par l'utilisateur sur la console : disque a 82%, seulement 4,8G
# disponibles, RAM sous pression avec 1,4G de swap utilise). Diagnostic
# reel avant toute action (jamais suppose) : `du -xh --max-depth=1`
# recursif a identifie precisement les postes reclamables :
#
#   (1) PCP (Performance Co-Pilot : pmcd/pmie/pmlogger, 1,1G dans
#       /var/log/pcp) - service OL8 PAR DEFAUT, jamais installe ni
#       utilise par cette usine (aucune reference dans jobs_table.csv,
#       confirme par recherche exhaustive) - pure surconsommation
#       heritee de l'image de base. Deux de ses services tournaient meme
#       en echec permanent ("pmlogger_daily.service failed",
#       "pmlogger_farm.service failed", confirmes en reel via
#       systemctl), preuve qu'il ne sert deja a rien de fonctionnel ici.
#       Corrige DEFINITIVEMENT (pas juste purge des logs qui
#       repousseraient sans fin) : services desactives et arretes.
#
#   (2) Cache dnf (/var/cache/dnf, 1,7G) - metadonnees et paquets .rpm
#       deja installes, jamais reutilises une fois l'installation faite.
#       Sans risque, regenere a la demande par le prochain dnf install.
#
# CE QUI N'EST VOLONTAIREMENT PAS TOUCHE, ET POURQUOI (jamais un
# nettoyage aveugle) : /var/ossec/queue/vd/feed (2,3G) est la base CVE
# ACTIVE du module Vulnerability Detector - taille normale et attendue
# pour cette fonctionnalite, pas un residu (181 fichiers seulement, 6
# de plus de 7 jours - aucun signe d'accumulation anormale). La
# supprimer forcerait un retelechargement complet couteux et
# desactiverait temporairement la detection de vulnerabilites - le
# vd-bloat-guardian (INFRA_003) s'occupe deja specifiquement du VRAI
# residu de ce module (/var/ossec/tmp/vd_*.tar, la version decompressee
# jetable, jamais le cache source lui-meme).
#
# PARTIE PERMANENTE (RUN, point #9 de la mission) : au-dela du
# nettoyage ponctuel ci-dessus, un timer hebdomadaire maintient le
# cache dnf et le journal systemd sous controle en continu - sans
# service a desactiver de nouveau (deja fait une fois pour de bon),
# seul un entretien recurrent reste necessaire.
set -uo pipefail
source "$VARS_FILE"

echo "[INFRA_005] Desactivation definitive de PCP (Performance Co-Pilot, jamais utilise par cette usine)..."
PCP_SERVICES="pmcd pmie pmie_farm pmlogger pmlogger_daily pmlogger_farm"
ANY_ACTIVE=0
for SVC in $PCP_SERVICES; do
  if systemctl list-unit-files "${SVC}.service" &>/dev/null; then
    ANY_ACTIVE=1
    systemctl disable --now "${SVC}.service" 2>/dev/null || true
  fi
done
if [ "$ANY_ACTIVE" -eq 1 ]; then
  echo "[INFRA_005] Purge des archives PCP deja accumulees (/var/log/pcp)..."
  find /var/log/pcp -type f -delete 2>/dev/null || true
  echo "[INFRA_005] PCP desactive et purge."
else
  echo "[INFRA_005] PCP deja absent/desactive, ignore."
fi

echo "[INFRA_005] Nettoyage du cache dnf..."
dnf clean all >/dev/null 2>&1 || true

echo "[INFRA_005] Etat disque apres nettoyage :"
df -h / | tail -n1

echo "[INFRA_005] Installation de l'entretien hebdomadaire permanent (timer)..."
MAINT_SCRIPT="/usr/local/sbin/wef-disk-hygiene.sh"
SERVICE_FILE="/etc/systemd/system/wef-disk-hygiene.service"
TIMER_FILE="/etc/systemd/system/wef-disk-hygiene.timer"

cat > "$MAINT_SCRIPT" << 'SCRIPTEOF'
#!/bin/bash
# Entretien disque hebdomadaire - genere par jobs/INFRA_005_DISK_HYGIENE.sh.
# Uniquement des actions sans risque (cache paquet regenerable, purge
# journal au-dela d'une retention raisonnable) - jamais de donnee de
# service metier touchee ici.
dnf clean all >/dev/null 2>&1 || true
journalctl --vacuum-time=14d >/dev/null 2>&1 || true
DISK_PCT=$(df --output=pcent / 2>/dev/null | tail -n1 | tr -dc '0-9')
if [ -n "$DISK_PCT" ] && [ "$DISK_PCT" -ge 85 ]; then
  logger -t wef-disk-hygiene "ALERTE : disque / toujours a ${DISK_PCT}% apres entretien de routine - verification manuelle necessaire."
fi
SCRIPTEOF
chmod 755 "$MAINT_SCRIPT"

cat > "$SERVICE_FILE" << 'UNITEOF'
[Unit]
Description=Entretien hebdomadaire du disque (cache dnf, journal systemd) - INFRA_005_DISK_HYGIENE

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/wef-disk-hygiene.sh
UNITEOF

cat > "$TIMER_FILE" << 'TIMEREOF'
[Unit]
Description=Declenche l'entretien disque une fois par semaine

[Timer]
OnCalendar=Sun *-*-* 03:00:00
RandomizedDelaySec=1800
Persistent=true

[Install]
WantedBy=timers.target
TIMEREOF

systemctl daemon-reload
systemctl enable --now wef-disk-hygiene.timer

if ! systemctl is-active wef-disk-hygiene.timer >/dev/null 2>&1; then
  echo "[INFRA_005] ERREUR : wef-disk-hygiene.timer n'est pas actif apres activation." >&2
  systemctl status wef-disk-hygiene.timer --no-pager >&2 || true
  exit 1
fi

echo "[INFRA_005] OK (PCP desactive, cache dnf purge, entretien hebdomadaire actif)."
exit 0
