#!/bin/bash
# ES_B001B_CPU_CHECK - WEF_ES_BLD_MINVCPUVERIFY - Verification vCPU min
# (seuil lu depuis MIN_VCPU_REQUIRED, vars.conf)
#
# AJOUTE LE 2026-09-08 (incident reel deploiement MIPREL2, voir
# docs/JOURNAL_TECHNIQUE.md) : seul le RAM etait verifie avant ce jour
# (ES_B001_RAM_CHECK) - aucun controle vCPU sur le role ELK_HOST (a la
# difference d'AGENT_HOST, voir MIN_VCPU_REQUIRED_AGENT). Un
# deploiement reel sur une VM a 1 seul vCPU a franchi ce controle RAM
# sans probleme, puis a echoue 30+ minutes plus loin sur WAZ_014
# (wazuh-indexer bloque en HTTP 503 bien au-dela du budget de sondage) -
# diagnostic reel : "nproc" = 1, "load average" ~2 (2 processus en
# attente de l'unique coeur en permanence), Elasticsearch + Logstash +
# Kibana + Wazuh Indexer tous actifs simultanement sur ce meme coeur
# unique - le bootstrap du plugin de securite OpenSearch (CPU-bound :
# generation de cles, creation d'index systeme) mettait plusieurs
# minutes au lieu de quelques secondes. Pas un bug logiciel : un
# sous-dimensionnement reel, invisible jusqu'a ce point precis de la
# chaine. Ce controle le detecte des le debut, avec un message clair,
# plutot qu'un timeout mysterieux 30 minutes plus tard.
set -uo pipefail
source "$VARS_FILE"
MIN_VCPU="${MIN_VCPU_REQUIRED:-2}"
VCPU_COUNT=$(nproc)
echo "[ES_B001B_CPU_CHECK] vCPU detectes : ${VCPU_COUNT} (seuil minimum configure : ${MIN_VCPU}, RESOURCE_PROFILE=${RESOURCE_PROFILE:-non defini})."
if [ "$VCPU_COUNT" -lt "$MIN_VCPU" ]; then
  echo "[ES_B001B_CPU_CHECK] ERREUR : vCPU insuffisants (minimum ${MIN_VCPU} requis par MIN_VCPU_REQUIRED, vars.conf). Cette usine fait tourner Elasticsearch + Logstash + Kibana + Wazuh Indexer (puis Wazuh Manager/Dashboard) EN PARALLELE sur le meme hote - sur 1 seul coeur, chaque demarrage (en particulier le bootstrap du plugin de securite OpenSearch, gros consommateur CPU) peut se mettre a durer plusieurs minutes au lieu de quelques secondes, jusqu'a depasser des budgets d'attente deja genereux plus loin dans la chaine (voir WAZ_014, incident reel du 2026-09-08). Ajoutez au moins un 2e vCPU a cette VM avant de continuer (VMware/VirtualBox : eteindre la VM, modifier ses parametres processeur, redemarrer)."
  exit 1
fi
echo "[ES_B001B_CPU_CHECK] OK."
exit 0
