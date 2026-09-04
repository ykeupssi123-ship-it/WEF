#!/bin/bash
# LS_026_FINAL - WEF_LS_BLD_STARTLGSTSH - Lancement final du collecteur
#
# CORRECTIF 2026-08-19 (incident reel wef-elk-core) : "systemctl enable
# --now" ne redemarre PAS un service deja actif - c'est un no-op sur la
# partie "start" si logstash tournait deja (seul "enable" au sens
# demarrage au boot est applique). Consequence reelle observee : un
# process Logstash lance lors d'un essai anterieur (avant les
# correctifs du jour sur le port syslog et la casse du keystore) est
# reste actif pendant plus de 2h ("Active: active (running) since ...")
# alors que LS_007/LS_020/LS_024/LS_B025_ARMED avaient entre-temps
# regenere une configuration correcte sur disque - jamais rechargee,
# puisque ce job ne l'a jamais force. LS_027 (en aval) a donc timeout
# indefiniment sur le meme vieux process en boucle d'erreur. Ce projet
# reconstruit sa configuration entierement a chaque passage (voir
# LS_024.sh : "toujours reconstruit depuis zero") - le job de demarrage
# doit donc TOUJOURS forcer un redemarrage reel pour matcher cette
# intention, jamais juste "s'assurer que quelque chose tourne".
echo "[LS_026_FINAL] Demarrage de Logstash..."
systemctl enable logstash 2>/dev/null || true
if ! systemctl restart logstash; then
  echo "[LS_026_FINAL] ERREUR : logstash.service n'a pas demarre. Diagnostic (journalctl -u logstash -n 30) :"
  journalctl -u logstash -n 30 --no-pager 2>/dev/null || true
  echo "[LS_026_FINAL] Voir aussi /var/log/logstash/*.log pour le detail complet."
  exit 1
fi
sleep 5
echo "[LS_026_FINAL] OK."
exit 0
