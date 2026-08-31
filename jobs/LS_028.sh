#!/bin/bash
# LS_028 - WEF_LS_RUN_MTRPOLL - Polling de l'API locale (9600)
#
# CORRIGE LE 2026-08-30 (incident reel wef-elk-core, reproduit en reel) :
# LS_027 (juste avant) ne verifie que le fichier de log de demarrage,
# pas la disponibilite reelle de l'API HTTP de monitoring (9600) - un
# ecart de quelques secondes existe entre "Logstash a ecrit sa ligne de
# demarrage" et "le listener HTTP 9600 accepte des connexions". Sans
# nouvelle tentative, ce job echoue par pure course de timing (confirme
# en reel : echec immediat, puis 9600 repond bien quelques secondes
# plus tard sans aucune autre action). Meme discipline que
# WAZ_020_VERIFY : "pas encore" n'est pas "jamais".
set -uo pipefail
source "$VARS_FILE"
echo "[LS_028] Verification de l'API de monitoring Logstash..."
TENTATIVES=6
INTERVALLE=5
i=1
while [ "$i" -le "$TENTATIVES" ]; do
  if curl -s -XGET http://127.0.0.1:9600/ -o /dev/null; then
    echo "[LS_028] OK (tentative ${i}/${TENTATIVES})."
    exit 0
  fi
  echo "[LS_028] API 9600 pas encore prete (tentative ${i}/${TENTATIVES})..."
  i=$((i + 1))
  [ "$i" -le "$TENTATIVES" ] && sleep "$INTERVALLE"
done
echo "[LS_028] ERREUR : API 9600 injoignable apres ${TENTATIVES} tentatives."
exit 1
