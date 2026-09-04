#!/bin/bash
# LS_007 - WEF_LS_BLD_FWPORT514 - Ouverture du port Syslog 514
#
# CORRECTIF 2026-08-18 (incident reel : crash loop Netty
# RejectedExecutionException sur l'entree TCP syslog de Logstash) :
# 514 est un port privilegie (<1024). Le service logstash tourne en
# utilisateur non-root (LS_003) et ne peut pas s'y binder directement -
# EACCES au demarrage, retries en boucle, Netty finit par rejeter des
# taches sur un event-loop-group deja en cours de destruction. Au lieu
# de donner CAP_NET_BIND_SERVICE au binaire Java (fragile : perdu a
# chaque reinstallation/maj du paquet logstash), on garde 514 comme
# facade publique et on le redirige vers LS_SYSLOG_INTERNAL_PORT (5514,
# non privilegie, voir vars.conf) via le pare-feu. Logstash (LS_020)
# n'ecoute reellement que sur 5514 - jamais besoin de droits root.
set -uo pipefail
source "$VARS_FILE"
echo "[LS_007] Ouverture du port interne ${LS_SYSLOG_INTERNAL_PORT}/tcp sur CollectZone (ecoute reelle de Logstash)..."
firewall-cmd --permanent --zone=CollectZone --add-port=${LS_SYSLOG_INTERNAL_PORT}/tcp
echo "[LS_007] Redirection facade publique ${LS_SYSLOG_PORT}/tcp -> ${LS_SYSLOG_INTERNAL_PORT}/tcp (port forwarding, evite tout bind privilegie par Logstash)..."
firewall-cmd --permanent --zone=CollectZone --add-forward-port=port=${LS_SYSLOG_PORT}:proto=tcp:toport=${LS_SYSLOG_INTERNAL_PORT}
firewall-cmd --reload
echo "[LS_007] OK."
exit 0
