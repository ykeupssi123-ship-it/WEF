#!/bin/bash
# LS_027 - WEF_LS_RUN_LOGPOLL - Analyse du fichier de demarrage
#
# CORRECTIF 2026-08-18 : jusqu'ici, un timeout se contentait de dire
# "pipeline non demarre" sans aucun detail - l'operateur devait aller
# chercher lui-meme dans journalctl/les logs pour savoir POURQUOI (ex :
# incident reel LS_B025_ARMED du 2026-08-14, keystore absent ->
# "Cannot evaluate ${FACTORY_INGEST_TOKEN}..." dans logstash-plain.log,
# ou le crash loop Netty RejectedExecutionException du port 514 corrige
# dans LS_007/LS_020). Meme reflexe que LS_026_FINAL desormais : sur
# timeout, on imprime nous-memes le diagnostic (statut systemd + fin des
# deux logs Logstash) au lieu de laisser l'operateur repartir de zero.
#
# CORRECTIF 2026-08-19 (incident reel wef-elk-core, decouvert APRES la
# resolution complete de l'incident 403/manage_index_templates - Logstash
# tournait alors reellement sans aucune erreur) : la detection cherchait
# la chaine litterale "Pipeline running" (singulier), alors que la vraie
# ligne ecrite par Logstash est "Pipelines running {:count=>1,
# :running_pipelines=>[...]}" (PLURIEL - c'est le message de
# logstash.agent confirmant que l'agent a fini de demarrer TOUTES ses
# pipelines, pas un message par pipeline individuelle). Cette faute de
# frappe existait depuis l'ecriture initiale du job et n'avait jamais ete
# revelee : sur toutes les executions precedentes, un vrai probleme
# (keystore absent, port privilegie, cle API sans privilege) faisait de
# toute facon echouer le pipeline avant meme d'atteindre ce message, donc
# le timeout etait "correct" pour de mauvaises raisons. Une fois ce vrai
# probleme reste le seul obstacle (Logstash demarrant reellement en ~8s),
# le bug de detection est devenu visible : timeout de 5 minutes complet
# alors que "Pipelines running" apparaissait dans les logs des la
# 2e seconde de polling. Corrige : recherche desormais "Pipelines
# running" (le pluriel exact ecrit par logstash.agent).
#
# CORRECTIF 2026-09-02 (incident reel, deploiement VM ELK_HOST Oracle
# Linux 8, decouvert le meme jour que le correctif ci-dessus dans
# jobs/LS_B025_ARMED.sh) : ce job ne regardait QUE le fichier
# logstash-plain.log. Or ce fichier peut se retrouver root:root (voir
# correctif LS_B025_ARMED) et devenir illisible en ecriture par le
# service logstash - alors que Logstash tourne en realite tres bien et
# ecrit bel et bien "Pipelines running", simplement ailleurs (journald,
# capture via `journalctl -u logstash`, non affecte par ce probleme de
# permissions car independant du systeme de fichiers). Resultat reel
# observe : 5 minutes de timeout complet, diagnostic final affichant
# pourtant "Pipelines running" dans son propre extrait `journalctl`,
# preuve que la detection cherchait au mauvais endroit. Le correctif
# LS_B025_ARMED regle la cause racine (proprietaire des fichiers) pour
# tout nouveau deploiement, mais on fiabilise EN PLUS la detection
# elle-meme ici, en profondeur ("belt and suspenders") : on verifie
# desormais le fichier ET journalctl a chaque iteration, n'importe lequel
# des deux suffit - ainsi un probleme de permissions futur, une rotation
# de logs, ou tout autre souci propre au fichier ne pourra plus a lui
# seul bloquer silencieusement cette detection alors que Logstash tourne
# normalement.
set -uo pipefail
source "$VARS_FILE"
echo "[LS_027] Attente du log 'Pipelines running'..."
for i in $(seq 1 60); do
  if grep -q "Pipelines running" /var/log/logstash/logstash-plain.log 2>/dev/null; then
    echo "[LS_027] OK (detecte via le fichier logstash-plain.log)."
    exit 0
  fi
  if journalctl -u logstash --no-pager 2>/dev/null | grep -q "Pipelines running"; then
    echo "[LS_027] OK (detecte via journalctl -u logstash - fichier logstash-plain.log inaccessible ou en retard, voir correctif 2026-09-02 dans jobs/LS_B025_ARMED.sh)."
    exit 0
  fi
  sleep 5
done
echo "[LS_027] ERREUR : timeout, pipeline non demarre. Diagnostic automatique :" >&2
echo "[LS_027] --- systemctl status logstash ---" >&2
systemctl status logstash --no-pager -l 2>&1 | tail -20 >&2 || true
echo "[LS_027] --- journalctl -u logstash (30 dernieres lignes) ---" >&2
journalctl -u logstash -n 30 --no-pager 2>&1 >&2 || true
echo "[LS_027] --- tail /var/log/logstash/logstash-plain.log ---" >&2
tail -40 /var/log/logstash/logstash-plain.log 2>&1 >&2 || echo "[LS_027] (fichier absent ou illisible)" >&2
echo "[LS_027] --- tail /var/log/logstash/logstash-deprecation.log ---" >&2
tail -20 /var/log/logstash/logstash-deprecation.log 2>&1 >&2 || true
echo "[LS_027] Fin du diagnostic automatique. Voir aussi GUIDE_EXPLOITATION.txt." >&2
exit 1
