#!/bin/bash
# INFRA_003_DEVNULL_GUARDIAN - Garde permanente contre la corruption de
# /dev/null ET contre le remplissage disque recurrent du cache CVE
# Vulnerability Detector (deux incidents reels distincts, tous deux
# constates plusieurs fois dans la meme session - regroupes ici sous
# un seul job de "resilience permanente" plutot que deux jobs quasi-
# identiques, voir le detail de chaque garde plus bas)
#
# AJOUTE LE 2026-08-30 (incident reel wef-elk-core, RECURRENT - constate
# 4 fois en une seule session : /dev/null se retrouve transforme en
# fichier ordinaire pendant la chaine, coupant sshd (qui ne peut plus
# l'ouvrir pour chaque nouvelle session) et donc tout acces distant).
# lib/commun.sh (check_dev_null) repare deja ca AVANT chaque job de
# l'orchestrateur - insuffisant : la corruption a ete observee pendant
# l'EXECUTION d'un job (JVM lourde en cours de demarrage) et reste donc
# active jusqu'au prochain job, ce qui suffit a couper l'acces SSH
# pendant plusieurs minutes a chaque fois.
#
# Cause exacte non identifiee avec certitude malgre investigation reelle
# (surveillance auditd posee : -w /dev/null -p wa - n'a capture aucun
# evenement au moment de l'incident, ce qui suggere que le noeud
# peripherique lui-meme est remplace d'une maniere qui echappe a une
# simple surveillance de chemin, plutot qu'une simple ecriture/attribut
# modifie sur l'inode existant - cf. le commentaire deja present dans
# check_dev_null, qui evoquait une fenetre de reattachement devtmpfs).
# Honnete plutot que de pretendre un diagnostic complet : ce job
# n'ELIMINE PAS la cause, il rend ses CONSEQUENCES invisibles en
# reparant en continu, ce qui suffit a l'objectif "zero intervention
# manuelle" meme sans connaitre le declencheur exact.
#
# Mecanisme : un timer systemd (pas un service demon classique, pour
# rester reveille meme si quelque chose de plus grave arrive) verifie
# et repare /dev/null toutes les 3 secondes - cout negligeable, latence
# de coupure SSH ramenee de "plusieurs minutes, jusqu'au prochain job"
# a "quelques secondes maximum".
set -uo pipefail
source "$VARS_FILE"

REPAIR_SCRIPT="/usr/local/sbin/repair-devnull.sh"
SERVICE_FILE="/etc/systemd/system/devnull-guardian.service"
TIMER_FILE="/etc/systemd/system/devnull-guardian.timer"

echo "[INFRA_003] Installation du script de reparation ${REPAIR_SCRIPT}..."
cat > "$REPAIR_SCRIPT" << 'SCRIPTEOF'
#!/bin/bash
# Repare /dev/null s'il n'est plus un peripherique caractere (voir
# jobs/INFRA_003_DEVNULL_GUARDIAN.sh pour le contexte complet). Jamais
# de log verbeux ici (tourne toutes les 3s en permanence) - seule une
# reparation reelle est journalisee.
if [ ! -c /dev/null ]; then
  logger -t devnull-guardian "ALERTE : /dev/null n'est plus un peripherique caractere - reparation automatique."
  rm -f /dev/null
  mknod -m 666 /dev/null c 1 3
  chown root:root /dev/null
  command -v restorecon >/dev/null 2>&1 && restorecon /dev/null 2>/dev/null || true
  logger -t devnull-guardian "/dev/null repare."
fi
SCRIPTEOF
chmod 755 "$REPAIR_SCRIPT"

echo "[INFRA_003] Installation du service/timer systemd..."
cat > "$SERVICE_FILE" << 'UNITEOF'
[Unit]
Description=Verification/reparation de /dev/null (INFRA_003_DEVNULL_GUARDIAN)

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/repair-devnull.sh
UNITEOF

cat > "$TIMER_FILE" << 'TIMEREOF'
[Unit]
Description=Declenche la verification de /dev/null toutes les 3 secondes

[Timer]
OnBootSec=5s
OnUnitActiveSec=3s
AccuracySec=1s

[Install]
WantedBy=timers.target
TIMEREOF

systemctl daemon-reload
systemctl enable --now devnull-guardian.timer

if ! systemctl is-active devnull-guardian.timer >/dev/null 2>&1; then
  echo "[INFRA_003] ERREUR : devnull-guardian.timer n'est pas actif apres activation." >&2
  systemctl status devnull-guardian.timer --no-pager >&2 || true
  exit 1
fi

# GARDE DISQUE (ajoutee le meme jour, meme incident session) : le module
# Vulnerability Detector de wazuh-manager re-extrait
# /var/ossec/tmp/vd_*.tar (8,5G, decompresse depuis un .tar.xz de 397M -
# ratio x21) A CHAQUE REDEMARRAGE DU MANAGER (WAZ_015, rejoue par chaque
# passage de l'orchestrateur), sans jamais le nettoyer lui-meme -
# constate deux fois EN REEL dans la meme session, chaque fois avec
# EXACTEMENT le meme fichier/la meme taille. Deja documente comme
# incident connu par MNT_purge_rapide_disque.sh (geste manuel,
# ON_DEMAND) - insuffisant pour l'objectif "zero intervention manuelle"
# puisque rien ne l'appelle automatiquement. Le fichier .tar est un pur
# scratch de decompression (le .tar.xz d'origine, rechargeable, est
# toujours conserve a cote) : sans risque de le supprimer des qu'il
# existe.
#
# CORRIGE LE 2026-08-31 (meme jour, incident reel : regression auto-
# infligee decouverte en diagnostiquant pourquoi le module
# vulnerability-scanner echouait a repetition) : "des qu'il existe" etait
# une hypothese FAUSSE, jamais verifiee a l'epoque - confirme en reel
# via /var/ossec/logs/ossec.log : "Error opening file during
# decompression. Error: Failed to open 'tmp/vd_1.0.0_vd_4.13.0.tar'" -
# ce garde (cycle de 60s) a authentiquement supprime le fichier PENDANT
# que le module etait encore en train de le lire/extraire, une vraie
# condition de course introduite par ce job lui-meme. Le fichier n'est
# pas un scratch "mort des l'apparition" : il reste activement utilise
# pendant toute la duree de la decompression (observee en reel entre 1
# et 2 minutes). Corrige : seuls les fichiers de plus de 10 minutes
# (600s, mtime) sont desormais supprimes - couvre toujours le vrai
# probleme d'origine (fichier abandonne pendant des HEURES sans jamais
# etre nettoye par le module) sans jamais toucher une extraction encore
# en cours.
DISK_REPAIR_SCRIPT="/usr/local/sbin/repair-vd-bloat.sh"
DISK_SERVICE_FILE="/etc/systemd/system/vd-bloat-guardian.service"
DISK_TIMER_FILE="/etc/systemd/system/vd-bloat-guardian.timer"

echo "[INFRA_003] Installation de la garde disque (cache CVE Vulnerability Detector)..."
cat > "$DISK_REPAIR_SCRIPT" << 'SCRIPTEOF'
#!/bin/bash
# Supprime /var/ossec/tmp/vd_*.tar UNIQUEMENT s'il a plus de 10 minutes
# (voir jobs/INFRA_003_DEVNULL_GUARDIAN.sh pour le contexte complet et
# l'incident reel de condition de course qui a motive ce delai) - jamais
# le .tar.xz source, jamais journalise si rien a faire.
find /var/ossec/tmp -maxdepth 1 -name 'vd_*.tar' -mmin +10 -print 2>/dev/null | while read -r f; do
  logger -t vd-bloat-guardian "ALERTE : $f present depuis plus de 10 min (cache CVE non nettoye par Vulnerability Detector) - suppression automatique."
  rm -f "$f"
done
SCRIPTEOF
chmod 755 "$DISK_REPAIR_SCRIPT"

cat > "$DISK_SERVICE_FILE" << 'UNITEOF'
[Unit]
Description=Nettoyage du cache CVE Vulnerability Detector si non nettoye

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/repair-vd-bloat.sh
UNITEOF

cat > "$DISK_TIMER_FILE" << 'TIMEREOF'
[Unit]
Description=Declenche la verification du cache CVE toutes les 60 secondes

[Timer]
OnBootSec=30s
OnUnitActiveSec=60s
AccuracySec=5s

[Install]
WantedBy=timers.target
TIMEREOF

systemctl daemon-reload
systemctl enable --now vd-bloat-guardian.timer

if ! systemctl is-active vd-bloat-guardian.timer >/dev/null 2>&1; then
  echo "[INFRA_003] ERREUR : vd-bloat-guardian.timer n'est pas actif apres activation." >&2
  systemctl status vd-bloat-guardian.timer --no-pager >&2 || true
  exit 1
fi

echo "[INFRA_003] OK (devnull-guardian.timer + vd-bloat-guardian.timer actifs)."
exit 0
