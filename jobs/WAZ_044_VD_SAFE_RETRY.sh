#!/bin/bash
# WAZ_044_VD_SAFE_RETRY - WEF_WAZ_RUN_VDRETRY - Relance surveillee du
# module Vulnerability Detector
#
# AJOUTE LE 2026-08-31 (point #9 de la mission - jobs RUN rejouables
# pour chaque erreur reelle rencontree - demande explicite de
# l'utilisateur, suite a un incident reel sur wef-elk-core). Symptome
# reel observe cote utilisateur : la case "Vulnerability Detection" du
# Dashboard restait a "0" partout sur un agent jamais durci - signe reel
# d'un module casse, pas d'un systeme sain (confirme par l'utilisateur
# lui-meme, a juste titre).
#
# DIAGNOSTIC REEL COMPLET (trois causes empilees, chacune confirmee par
# lecture directe de /var/ossec/logs/ossec.log, jamais supposee) :
#   (1) Le module a besoin de decompresser ~8,5G (depuis un .tar.xz de
#       397M) dans /var/ossec/tmp/ - echoue purement et simplement si le
#       disque n'a pas cette marge disponible ("No space left on
#       device" / "Write failed" / "Error opening file during
#       decompression" selon le moment exact de l'echec).
#   (2) INFRA_003_DEVNULL_GUARDIAN.sh (vd-bloat-guardian, timer 60s)
#       supprimait ce fichier .tar DES QU'IL EXISTAIT - une condition de
#       course reelle qui l'a authentiquement efface PENDANT que ce
#       module l'utilisait encore. Corrige ce meme jour dans
#       INFRA_003_DEVNULL_GUARDIAN.sh (delai de 10 minutes avant
#       suppression).
#   (3) Le disque de cette VM etait structurellement trop petit (26G)
#       pour accueillir 8,5G de decompression EN PLUS du reste - corrige
#       ce meme jour par extension reelle du disque (60G).
#
# CE JOB, pour un rejeu futur sans repeter tout ce diagnostic : verifie
# la marge disque AVANT de relancer (jamais a l'aveugle), nettoie tout
# fichier .tar partiel abandonne (meme garde-fou d'age que le guardian -
# jamais un fichier potentiellement en cours d'usage), relance
# wazuh-manager, et attend une confirmation REELLE de succes ou d'echec
# dans le journal (jamais un "OK" qui ne repose que sur l'absence
# d'exception shell).
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

MARGE_MIN_GO=10

echo "[WAZ_044] Verification de la marge disque disponible (minimum requis : ${MARGE_MIN_GO}G)..."
DISPO_KO=$(df --output=avail / 2>/dev/null | tail -n1 | tr -dc '0-9')
DISPO_GO=$(( DISPO_KO / 1024 / 1024 ))
if [ "$DISPO_GO" -lt "$MARGE_MIN_GO" ]; then
  echo "[WAZ_044] ERREUR : seulement ${DISPO_GO}G disponibles sur /, minimum requis ${MARGE_MIN_GO}G. Liberez de l'espace avant de relancer (voir INFRA_005_DISK_HYGIENE.sh)." >&2
  exit 1
fi
echo "[WAZ_044] ${DISPO_GO}G disponibles, marge suffisante."

echo "[WAZ_044] Nettoyage de tout fichier .tar partiel abandonne (plus de 10 min, jamais un fichier en cours d'usage)..."
find /var/ossec/tmp -maxdepth 1 -name 'vd_*.tar' -mmin +10 -delete 2>/dev/null || true

# CORRIGE LE 2026-09-09 (incident reel, meme VM, stade avance du
# deploiement - ES+LS+KB+WAZ tous actifs simultanement) : "tail -n 50"
# suivi d'un grep repete toutes les 5s supposait implicitement que le
# message cible resterait visible dans les 50 dernieres lignes assez
# longtemps pour etre vu. Preuve reelle : a ce stade, ossec.log est tres
# bavard (wazuh-db se reconnecte toutes les ~10s, syscheckd/logcollector
# journalisent aussi en continu, niveau debug actif) - largement plus de
# 50 lignes peuvent s'ecrire entre deux sondages, poussant le message
# (demarrage OU erreur) hors de la fenetre AVANT le sondage suivant :
# `wazuh-manager` confirme actif (systemctl status), aucune ligne
# Vulnerability* visible dans les 50 dernieres lignes a aucun moment -
# jamais un vrai blocage, juste un defaut de detection.
# Corrige par une fenetre de lecture CROISSANTE : le nombre de lignes du
# journal est fige au moment du redemarrage, chaque sondage relit TOUT
# ce qui a ete ecrit DEPUIS ce point precis (jamais de fenetre glissante
# qui peut perdre un message, jamais de risque de reagir a une ancienne
# ligne d'un run precedent). Budget egalement remonte (meme discipline
# que WAZ_CONVERGENT_TEST_TIMEOUT_SEC/WAZ_INDEX_VERIFY_TIMEOUT_SEC le
# meme jour) : la contention reelle observee a ce stade avance de la
# chaine (tous les services majeurs actifs a la fois) justifie plus que
# les 6 minutes d'origine.
OSSEC_LOG=/var/ossec/logs/ossec.log
RESTART_LINE=$(wc -l < "$OSSEC_LOG" 2>/dev/null || echo 0)

echo "[WAZ_044] Redemarrage de wazuh-manager..."
systemctl restart wazuh-manager 2>/dev/null || true
if ! wait_for_service_active wazuh-manager 120 5; then
  echo "[WAZ_044] ERREUR : wazuh-manager n'a pas redemarre proprement." >&2
  exit 1
fi

# CORRIGE LE 2026-09-09 (2e incident reel le meme jour, VM neuve) : la
# version precedente capturait "tail -n +N" dans une variable bash
# (NEW_LINES="$(...)"), puis retestait via "echo "$NEW_LINES" | grep" -
# a echoue a detecter un message de succes pourtant reellement present
# et confirme par lecture manuelle directe du fichier ("grep -c" sur
# le meme fichier, a l'instant du diagnostic, l'a bien trouve). Cause
# exacte non confirmee (soupconne : cout/fragilite de faire transiter
# des dizaines de milliers de lignes par une variable shell puis un
# "echo", sur un journal tres volumineux et croissant) - jamais suppose
# resolu sans preuve : corrige en revenant a un pipeline direct
# "tail | grep", strictement le meme que celui verifie manuellement en
# reel sur le journal en echec, sans jamais transiter par une variable
# intermediaire.
WAZ_VD_RETRY_TIMEOUT_SEC="${WAZ_VD_RETRY_TIMEOUT_SEC:-600}"
echo "[WAZ_044] Attente de la confirmation reelle du module (jusqu'a ${WAZ_VD_RETRY_TIMEOUT_SEC}s, decompression 8,5G observee)..."
for i in $(seq 1 $((WAZ_VD_RETRY_TIMEOUT_SEC / 5))); do
  if tail -n +$((RESTART_LINE + 1)) "$OSSEC_LOG" 2>/dev/null | grep -q "Vulnerability scanner module started"; then
    echo "[WAZ_044] OK (module demarre et confirme actif dans le journal reel)."
    exit 0
  fi
  if tail -n +$((RESTART_LINE + 1)) "$OSSEC_LOG" 2>/dev/null | grep -qE "VulnerabilityScannerFacade::start: (Error|Write failed)"; then
    echo "[WAZ_044] ERREUR : le module a signale un echec reel dans le journal - voir ${OSSEC_LOG}." >&2
    tail -n +$((RESTART_LINE + 1)) "$OSSEC_LOG" 2>/dev/null | grep -E "VulnerabilityScannerFacade::start: (Error|Write failed)" | tail -n 10 >&2
    exit 1
  fi
  sleep 5
done

echo "[WAZ_044] ERREUR : timeout, aucune confirmation de demarrage ni d'echec explicite trouvee dans le journal apres ${WAZ_VD_RETRY_TIMEOUT_SEC}s (fenetre complete depuis le redemarrage, ligne ${RESTART_LINE})." >&2
exit 1
