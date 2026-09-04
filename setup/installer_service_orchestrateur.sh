#!/bin/bash
# installer_service_orchestrateur.sh - AJOUTE LE 2026-08-19 (incident reel
# wef-elk-core, meme journee que le passage a WAZ_018_NET)
#
# PROBLEME REEL CONSTATE : ./orchestrator.sh lance directement dans une
# session SSH interactive (PuTTY) est un ENFANT de cette session. Quand
# WAZ_018_NET (crash-test reseau, coupe volontairement TOUT le trafic
# sortant pour simuler une panne et verifier que Wazuh s'en remet seul)
# a coupe le reseau, la session SSH elle-meme a fini par etre jugee
# morte par sshd (plus moyen d'envoyer le moindre paquet, y compris les
# keepalives) - qui a alors envoye SIGHUP au shell et a tout son groupe
# de processus, TUANT orchestrator.sh en plein milieu de la chaine.
# Preuve directe : WAZ_018_NET est bien marque OK dans l'historique
# (a eu le temps de finir et d'ecrire son marqueur AVANT que sshd ne
# tranche la connexion), mais WAZ_019_FLOOD n'a JAMAIS ete lance du tout
# ("Aucune execution enregistree") - l'orchestrateur est mort entre les
# deux, pas a cause d'un bug de script mais a cause du lien de parente
# process SSH <- shell <- orchestrator.sh.
#
# CE QUE NE REGLE PAS "reconnectez-vous et relancez" : chaque
# redemarrage manuel de ./orchestrator.sh depend d'un operateur present
# au bon moment - inacceptable pour une usine qu'on veut vendre comme
# automatisee de bout en bout, et strictement necessaire seulement le
# jour ou WAZ_018_NET tourne (mais reste un point de fragilite reel
# n'importe quand : toute coupure reseau, meme non voulue, tuerait de la
# meme facon un orchestrateur lance en direct dans un terminal).
#
# CORRECTIF : ce script installe orchestrator.sh comme un VRAI service
# systemd (wef-orchestrateur.service, Type=oneshot). Un service systemd
# n'est PAS un enfant de la session SSH qui l'a demarre - il est
# supervise par PID 1 (systemd lui-meme), totalement independant de tout
# terminal. Une coupure reseau, volontaire (WAZ_018_NET) ou accidentelle,
# n'a plus AUCUN effet sur lui : il continue de tourner et de progresser
# dans jobs_table.csv exactement comme avant, que quelqu'un soit
# connecte pour le regarder ou non. On se reconnecte simplement ensuite
# pour consulter son etat (systemctl status / journalctl / bin/monitoring.sh
# / bin/view_history.sh - tous continuent de fonctionner normalement).
#
# A LANCER UNE SEULE FOIS (racine, root) - idempotent, peut etre relance
# sans risque si le chemin d'installation change (ex: migration future
# hors de /tmp, deja signalee comme point de vigilance dans le dossier
# d'exploitation).
#
# Usage apres installation :
#   systemctl start wef-orchestrateur     # lance l'orchestrateur, detache de tout terminal
#   systemctl status wef-orchestrateur    # etat du dernier lancement (actif/reussi/echoue)
#   journalctl -u wef-orchestrateur -f    # suivre en direct (optionnel, purement pour observer)
#   systemctl stop wef-orchestrateur      # n'arrete PAS le job en cours proprement (voir note ci-dessous)
set -uo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "ERREUR : ce script doit etre lance en root (installation d'un service systemd)." >&2
  exit 1
fi

if ! command -v systemctl &>/dev/null; then
  echo "ERREUR : systemctl introuvable - cette machine ne semble pas utiliser systemd. Installation impossible." >&2
  exit 1
fi

# CORRIGE LE 2026-09-04 (reorganisation racine/bin/setup) : ce script vit
# desormais dans setup/, jamais a la racine - SCRIPT_DIR doit remonter
# d'un niveau pour continuer a designer la racine reelle du projet
# (ou vivent orchestrator.sh, vars.conf, jobs_table.csv).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIT_PATH="/etc/systemd/system/wef-orchestrateur.service"

echo "[installer_service_orchestrateur] Installation du service pour : ${SCRIPT_DIR}/orchestrator.sh"

if [ ! -x "${SCRIPT_DIR}/orchestrator.sh" ]; then
  echo "ERREUR : ${SCRIPT_DIR}/orchestrator.sh introuvable ou non executable." >&2
  exit 1
fi

# CORRECTIF 2026-09-02 (incident reel, deploiement VM ELK_HOST Oracle Linux
# 8, SELinux Enforcing par defaut) : quand ce dossier vit sous /root (clone
# fait en tant que root dans son propre home, cas le plus courant), les
# fichiers heritent du contexte SELinux "admin_home_t". Un service systemd
# tourne dans le domaine "init_t", qui n'a PAS le droit d'executer du
# contenu "admin_home_t" - "systemctl start" echoue alors immediatement
# avec "status=203/EXEC" (le fichier a pourtant les bons droits Unix +x,
# rien a voir avec des permissions classiques). Confirme en reel via
# `ausearch -m avc -ts recent` : "denied { execute } ... scontext=...
# init_t ... tcontext=... admin_home_t". Plutot que de laisser chaque
# operateur decouvrir et diagnostiquer ca a la main (vecu : plusieurs
# heures de debogage en direct), on relabelle nous-memes, en amont,
# UNIQUEMENT si SELinux est actif et si le contexte actuel n'est pas deja
# un contexte "executable par un service" (bin_t/usr_t couvrent les deux
# emplacements usuels /root et /opt) - idempotent, sans effet si SELinux
# est absent/desactive (autres distributions) ou si le contexte est deja
# correct (ex: dossier deja sous /opt, relabel automatique par restorecon).
if command -v getenforce &>/dev/null && [ "$(getenforce 2>/dev/null)" = "Enforcing" ]; then
  CURRENT_CTX="$(stat -c '%C' "${SCRIPT_DIR}/orchestrator.sh" 2>/dev/null | cut -d: -f3)"
  if [ "$CURRENT_CTX" != "bin_t" ] && [ "$CURRENT_CTX" != "usr_t" ]; then
    echo "[installer_service_orchestrateur] SELinux Enforcing detecte, contexte actuel '${CURRENT_CTX:-inconnu}' non executable par un service - application du contexte 'bin_t' sur ${SCRIPT_DIR}..."
    if ! command -v semanage &>/dev/null; then
      echo "[installer_service_orchestrateur] 'semanage' absent - installation de policycoreutils-python-utils..."
      dnf install -y policycoreutils-python-utils >/dev/null 2>&1 || yum install -y policycoreutils-python-utils >/dev/null 2>&1 || true
    fi
    if command -v semanage &>/dev/null && command -v restorecon &>/dev/null; then
      semanage fcontext -a -t bin_t "${SCRIPT_DIR}(/.*)?" 2>/dev/null || true
      restorecon -Rv "${SCRIPT_DIR}" >/dev/null
      echo "[installer_service_orchestrateur] Contexte SELinux corrige."
    else
      echo "[installer_service_orchestrateur] ATTENTION : impossible d'installer/utiliser semanage+restorecon - si 'systemctl start' echoue ensuite avec status=203/EXEC, c'est SELinux (voir ausearch -m avc -ts recent) ; corrigez manuellement ou deplacez ce dossier sous /opt." >&2
    fi
  fi
fi

cat > "$UNIT_PATH" << UNITEOF
[Unit]
Description=WAZ_ELK_FACTORY - Orchestrateur (ordonnanceur de jobs)
# Volontairement AUCUNE dependance reseau (After=network-online.target) :
# l'orchestrateur doit pouvoir demarrer et progresser meme si le reseau
# est instable ou volontairement coupe (crash-test WAZ_018_NET), c'est
# precisement le scenario que ce service existe pour bien traverser.
After=multi-user.target

[Service]
Type=oneshot
WorkingDirectory=${SCRIPT_DIR}
ExecStart=${SCRIPT_DIR}/orchestrator.sh
User=root
# RemainAfterExit=no (defaut) : "systemctl status" montre "inactive"
# apres une reussite et "failed" apres un exit 1 (orchestrator.sh sort
# en 1 sur echec de job) - visibilite immediate de l'issue reelle, sans
# avoir besoin d'etre reste connecte pour la voir en direct.
# Sortie standard/erreur du service capturee par journald automatiquement
# (journalctl -u wef-orchestrateur) - en plus des logs deja ecrits par
# l'orchestrateur lui-meme dans logs/ et state/history/ (aucune perte,
# simple redondance utile).

[Install]
WantedBy=multi-user.target
UNITEOF

echo "[installer_service_orchestrateur] Unite ecrite dans ${UNIT_PATH}."
systemctl daemon-reload
echo "[installer_service_orchestrateur] OK."
echo ""
echo "Pour lancer l'orchestrateur en service (detache de toute session SSH) :"
echo "  systemctl start wef-orchestrateur"
echo "Pour suivre en direct (facultatif, n'affecte pas l'execution) :"
echo "  journalctl -u wef-orchestrateur -f"
echo "Pour verifier l'issue apres coup (meme apres une reconnexion) :"
echo "  systemctl status wef-orchestrateur"
echo "  ./bin/monitoring.sh"
echo "  ./bin/view_history.sh <JOB_ID>"
exit 0
