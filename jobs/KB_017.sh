#!/bin/bash
# KB_017 - WEF_KB_BLD_KSTINIT - Initialisation du coffre de secrets
#
# CORRECTIF 2026-08-14 (audit systemique suite a l'incident LS_B025_ARMED) :
# "kibana-keystore create" se declarait OK sans jamais verifier que le
# fichier avait reellement ete cree - meme famille de bug qui a fait
# planter Logstash en boucle sur VM1 (voir README, incident 17).
set -uo pipefail
source "$VARS_FILE"
if [ -f /etc/kibana/kibana.keystore ]; then
  echo "[KB_017] Keystore deja initialise, ignore."
  echo "[KB_017] OK."
  exit 0
fi
# CORRIGE le 2026-09-01 (meme defaut reel trouve et corrige sur
# ES_021.sh le meme jour - meme cause, meme classe de bug - voir
# docs/JOURNAL_TECHNIQUE.md) : execute desormais comme KB_USER (jamais
# root), coherent avec le proprietaire reel de /etc/kibana, et la sortie
# reelle de la commande est desormais capturee et affichee en cas
# d'echec plutot que de deviner apres coup.
echo "[KB_017] Creation du keystore Kibana (utilisateur ${KB_USER})..."
KEYSTORE_OUT="$(sudo -u "${KB_USER}" /usr/share/kibana/bin/kibana-keystore create < /dev/null 2>&1)"
KEYSTORE_RC=$?
echo "$KEYSTORE_OUT"
if [ $KEYSTORE_RC -ne 0 ]; then
  echo "[KB_017] ERREUR : 'kibana-keystore create' a rendu le code ${KEYSTORE_RC}. Sortie ci-dessus." >&2
  exit 1
fi
if [ ! -f /etc/kibana/kibana.keystore ]; then
  echo "[KB_017] ERREUR : /etc/kibana/kibana.keystore n'existe toujours pas apres 'kibana-keystore create' (code sortie ${KEYSTORE_RC})." >&2
  exit 1
fi
echo "[KB_017] OK (fichier confirme present)."
exit 0
