#!/bin/bash
# INFRA_006_AGENT_RESOURCE_CHECK - WEF_INFRA_BLD_MINRESVERIFY - Verification
# des ressources minimales sur AGENT_HOST (VM2 et tout hote Linux supplementaire)
#
# AJOUTE LE 2026-08-31 - angle mort reel signale par l'operateur : ELK_HOST
# a son propre controle bloquant depuis le debut du projet (ES_B001_RAM_
# CHECK, voir vars.conf), mais AGENT_HOST n'a jamais eu d'equivalent -
# aucun job n'empechait de lancer l'orchestrateur sur une machine sous-
# dimensionnee, l'echec ne serait apparu que plus tard, sur un symptome
# indirect (Filebeat qui plante, installation dnf qui echoue faute
# d'espace...) sans jamais pointer la vraie cause. Corrige avec le meme
# principe qu'ES_B001 : verification explicite, EN PREMIER dans la
# chaine (avant toute installation), echec dur et immediat si la machine
# est sous le seuil - jamais un avertissement ignorable.
#
# Seuils volontairement bas (voir vars.conf) : Filebeat/Metricbeat/agent
# Wazuh sont des binaires legers (quelques dizaines de Mo chacun), sans
# JVM a dimensionner - rien a voir avec les seuils d'ELK_HOST (qui doit
# faire tourner 3 moteurs JVM en parallele sur la meme machine).
#
# POSITION DANS LA CHAINE : ce job devient le SEUL point d'entree
# (IN_COND=NONE) du role AGENT_HOST - FB_001, INFRA_002 et WAG_001
# (jusqu'ici tous les trois independants, IN_COND=NONE) dependent
# desormais de sa reussite (voir jobs_table.csv). Encore jamais teste
# en conditions reelles sur une vraie VM2 (le deploiement d'agent n'a
# pas encore ete fait au moment ou ce job est ecrit) - a verifier des
# le premier lancement reel, meme discipline honnete que le kit Windows
# (jobs_windows/, "point de vigilance signale mais non teste").
set -uo pipefail
source "$VARS_FILE"

if [ "${ROLE}" != "AGENT_HOST" ]; then
  echo "[INFRA_006_AGENT_RESOURCE_CHECK] ROLE=${ROLE}, ce job ne concerne que AGENT_HOST. Ignore."
  echo "[INFRA_006_AGENT_RESOURCE_CHECK] OK."
  exit 0
fi

MIN_RAM="${MIN_RAM_GB_REQUIRED_AGENT:-2}"
MIN_DISK="${MIN_DISK_GB_REQUIRED_AGENT:-15}"
MIN_VCPU="${MIN_VCPU_REQUIRED_AGENT:-1}"

RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
DISK_GB=$(df --output=avail -BG / 2>/dev/null | tail -n1 | tr -dc '0-9')
VCPU=$(nproc)

echo "[INFRA_006_AGENT_RESOURCE_CHECK] Detecte : ${VCPU} vCPU, ${RAM_GB} Go RAM, ${DISK_GB} Go disque libre sur / (seuils minimums : ${MIN_VCPU} vCPU / ${MIN_RAM} Go RAM / ${MIN_DISK} Go disque)."

ECHEC=0
if [ "$VCPU" -lt "$MIN_VCPU" ]; then
  echo "[INFRA_006_AGENT_RESOURCE_CHECK] ERREUR : ${VCPU} vCPU detecte(s), minimum ${MIN_VCPU} requis (MIN_VCPU_REQUIRED_AGENT, vars.conf)." >&2
  ECHEC=1
fi
if [ "$RAM_GB" -lt "$MIN_RAM" ]; then
  echo "[INFRA_006_AGENT_RESOURCE_CHECK] ERREUR : ${RAM_GB} Go RAM detectes, minimum ${MIN_RAM} Go requis (MIN_RAM_GB_REQUIRED_AGENT, vars.conf)." >&2
  ECHEC=1
fi
if [ "$DISK_GB" -lt "$MIN_DISK" ]; then
  echo "[INFRA_006_AGENT_RESOURCE_CHECK] ERREUR : ${DISK_GB} Go disque libre detectes sur /, minimum ${MIN_DISK} Go requis (MIN_DISK_GB_REQUIRED_AGENT, vars.conf)." >&2
  ECHEC=1
fi

if [ "$ECHEC" -eq 1 ]; then
  echo "[INFRA_006_AGENT_RESOURCE_CHECK] Machine sous-dimensionnee - installation refusee avant meme de commencer (voir vars.conf pour ajuster les seuils si vous savez ce que vous faites)." >&2
  exit 1
fi

echo "[INFRA_006_AGENT_RESOURCE_CHECK] OK."
exit 0
