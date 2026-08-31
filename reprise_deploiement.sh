#!/bin/bash
# reprise_deploiement.sh - AIDE A LA DECISION avant de (re)lancer
# orchestrator.sh sur une machine. Repond a la question qui revient a
# chaque nouvelle machine : "je fais quoi maintenant, je desinstalle ou
# je relance juste ?" - en lisant l'etat REEL de la machine au lieu de
# le redeviner a chaque fois. A lancer depuis le dossier wazuh_factory_3/
# (a cote d'orchestrator.sh), AVANT ./orchestrator.sh.
#
# Ne modifie rien - lecture seule, verdict + commande exacte a lancer.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

echo "===================================================================="
echo " REPRISE DE DEPLOIEMENT - etat de cette machine"
echo "===================================================================="

if [ ! -f vars.conf ] || [ ! -f orchestrator.sh ]; then
  echo "ERREUR : ce script doit etre lance depuis le dossier wazuh_factory_3/"
  echo "         (vars.conf et orchestrator.sh introuvables ici : $HERE)"
  exit 1
fi
set -a; source vars.conf; set +a

echo ""
echo "--- RAM / DISQUE actuels ---"
free -h
df -h /
RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
DISK_PCT_FREE=$(df -P / | awk 'NR==2{print 100-$5+0}')
echo ""
echo "Seuils configures dans vars.conf : MIN_RAM_GB_REQUIRED=${MIN_RAM_GB_REQUIRED:-?} Go | MIN_DISK_FREE_PCT=${MIN_DISK_FREE_PCT:-?} %"
if [ -n "${MIN_RAM_GB_REQUIRED:-}" ] && [ "$RAM_GB" -lt "$MIN_RAM_GB_REQUIRED" ]; then
  echo "ATTENTION : RAM detectee (${RAM_GB} Go) < seuil configure - ES_B001_RAM_CHECK va bloquer le deploiement."
fi
if [ -n "${MIN_DISK_FREE_PCT:-}" ] && [ "$DISK_PCT_FREE" -lt "$MIN_DISK_FREE_PCT" ]; then
  echo "ATTENTION : disque libre (${DISK_PCT_FREE}%) < seuil configure - lancez d'abord maintenance/MNT_diagnostic.sh"
fi

echo ""
echo "--- Paquets ELK/Wazuh deja presents sur cette machine ---"
FOUND_PKG=$(rpm -qa 2>/dev/null | grep -Ei 'wazuh|elastic|logstash|kibana|filebeat|metricbeat|opensearch' || true)
if [ -z "$FOUND_PKG" ]; then
  echo "(aucun - machine vierge cote paquets)"
else
  echo "$FOUND_PKG"
fi

echo ""
echo "--- Etat orchestrator.sh (dossier state/) ---"
if [ ! -d state ] || [ -z "$(ls -A state 2>/dev/null)" ]; then
  NB_OK=0
else
  NB_OK=$(ls state/*.ok 2>/dev/null | wc -l)
fi
echo "$NB_OK job(s) marque(s) termine(s) dans state/."

echo ""
echo "===================================================================="
echo " VERDICT"
echo "===================================================================="
if [ -n "$FOUND_PKG" ] && [ "$NB_OK" -eq 0 ]; then
  echo "Paquets deja presents MAIS aucun etat orchestrator.sh ici : machine"
  echo "probablement issue d'une installation anterieure (autre archive,"
  echo "ou dossier state/ efface a la main). NE PAS relancer directement -"
  echo "l'orchestrateur croirait repartir de zero sur des paquets deja la,"
  echo "risque de configuration incoherente."
  echo ""
  echo ">>> A FAIRE : ./maintenance/MNT_purge_complete_reinstall.sh"
  echo "    puis relancez ce script."
elif [ "$NB_OK" -eq 0 ]; then
  echo "Machine vierge (aucun paquet, aucun etat) : premier lancement ici."
  echo ""
  echo ">>> A FAIRE : ./orchestrator.sh"
else
  echo "Un run precedent existe ($NB_OK job(s) deja marque(s) OK dans state/)."
  echo "Rejouer ./orchestrator.sh maintenant SAUTERA ces jobs (comportement"
  echo "normal - c'est fait pour reprendre apres un echec sans tout refaire)."
  echo ""
  NEEDS_JVM_RESET=""
  for cond in ES_JVM_OK LS_JVM_TUNED WAZ_INDXR_JVM_OK; do
    [ -f "state/${cond}.ok" ] && NEEDS_JVM_RESET="$NEEDS_JVM_RESET state/${cond}.ok"
  done
  if [ -n "$NEEDS_JVM_RESET" ]; then
    echo "ATTENTION : les jobs de heap JVM sont deja marques OK. Si vous avez"
    echo "change ES_JVM_HEAP_SIZE/LS_JVM_HEAP_SIZE/WAZ_INDEXER_JVM_HEAP_SIZE"
    echo "dans vars.conf DEPUIS ce run precedent, ces jobs ne se rejoueront"
    echo "PAS tout seuls et les anciennes valeurs resteront actives."
    echo ""
    echo ">>> Pour forcer la re-application des heaps actuels : "
    echo "    rm -f$NEEDS_JVM_RESET && ./orchestrator.sh"
    echo ">>> Pour repartir totalement a zero (tous les jobs rejoues) :"
    echo "    rm -rf state logs && ./orchestrator.sh"
  else
    echo ">>> A FAIRE : ./orchestrator.sh   (reprend la ou ca s'etait arrete)"
    echo ">>> Pour repartir totalement a zero a la place :"
    echo "    rm -rf state logs && ./orchestrator.sh"
  fi
fi
echo "===================================================================="
