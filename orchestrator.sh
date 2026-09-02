#!/bin/bash
# =====================================================================
#  WAZ_ELK_FACTORY (237 jobs) - ORCHESTRATEUR (ordonnanceur)
#  Meme moteur que wazuh_factory_2/orchestrator.sh : lit jobs_table.csv,
#  resout les dependances (IN_COND/OUT_COND) et execute les jobs un a
#  un, dans l'ordre permis par les dependances.
#  Ne contient AUCUNE donnee en dur : tout vient de vars.conf.
#
#  DEUX NIVEAUX DE FILTRAGE :
#   1) ROLE (ELK_HOST ou AGENT_HOST) - le "grand" choix de la machine.
#      ELK_HOST = VM1 (Elasticsearch/Logstash/Kibana/Wazuh, monolithique).
#      AGENT_HOST = TOUTE AUTRE machine (VM2, ou un hote Linux
#      supplementaire) qui fait tourner un ou plusieurs agents.
#   2) AGENT_COMPONENTS (liste, uniquement si ROLE=AGENT_HOST) - QUELS
#      agents tournent sur CETTE machine precise, parmi FILEBEAT,
#      METRICBEAT, WAZUH_AGENT. Les 3 peuvent cohabiter sur la MEME
#      machine (c'est le cas de VM2 par defaut) OU etre repartis sur
#      des machines differentes (c'est aussi possible - a vous de
#      choisir par machine via AGENT_COMPONENTS dans vars.conf).
#
#  ARRET AU PREMIER ECHEC (fail-fast), DELIBERE : les jobs suivants
#  dependent souvent de la reussite du precedent (config ecrite,
#  service demarre...) - continuer apres un echec risquerait
#  d'enchainer des jobs sur une base deja cassee. Chaque machine
#  (VM1, VM2, chaque hote d'agent) execute SA PROPRE instance de cet
#  orchestrateur : un echec sur une machine n'arrete jamais les autres,
#  qui tournent independamment.
#
#  A LA FIN (succes OU echec), un rapport est toujours ecrit dans
#  state/RAPPORT_EXECUTION.txt : jobs termines, job en echec le cas
#  echeant, jobs jamais atteints, scripts absents.
# =====================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export VARS_FILE="$SCRIPT_DIR/vars.conf"
source "$VARS_FILE"
source "$SCRIPT_DIR/lib/commun.sh"

mkdir -p "$STATE_DIR" "$LOG_DIR" "$WORK_TMP_DIR"
TS=$(date +%Y%m%d_%H%M%S)
RUN_LOG="$LOG_DIR/orchestrator_${TS}.log"
JOBS_CSV="$SCRIPT_DIR/jobs_table.csv"
REPORT_FILE="$STATE_DIR/RAPPORT_EXECUTION.txt"

# HISTORIQUE PAR JOB (ajoute le 2026-08-12) : un .ok ne garde que la
# DERNIERE reussite (ecrase a chaque re-execution) - insuffisant pour
# repondre a "ce job a tourne 10 fois aujourd'hui, je veux voir chacune
# des 10 sorties". Desormais, CHAQUE execution reelle (pas les jobs
# sautes car deja .ok) laisse une trace : une ligne dans le registre
# HISTORY_LEDGER (jamais reecrite, uniquement ajoutee) + un fichier de
# log dedie a CETTE execution precise dans HISTORY_DIR/<JOB_ID>/. Voir
# historique_job.sh a la racine pour consulter.
HISTORY_DIR="$STATE_DIR/history"
HISTORY_LEDGER="$STATE_DIR/JOBS_HISTORY.csv"
mkdir -p "$HISTORY_DIR"
[ -f "$HISTORY_LEDGER" ] || echo "TIMESTAMP,JOB_ID,JOB_NAME,RESULT,LOG_FILE" > "$HISTORY_LEDGER"

# Purge automatique de l'historique perime (SYSOUT), ajoutee le
# 2026-08-12 - equivalent fonctionnel de l'expiration d'une SYSOUT
# JCL/mainframe. Retention pilotee par HISTORY_RETENTION_DAYS (vars.conf,
# 7 jours par defaut en contexte demo). Silencieuse et rapide : ne doit
# jamais bloquer le demarrage meme si le script est absent ou echoue.
if [ -x "$SCRIPT_DIR/maintenance/MNT_purge_historique.sh" ]; then
  "$SCRIPT_DIR/maintenance/MNT_purge_historique.sh" >> "$RUN_LOG" 2>&1 || true
fi

# ETAT VIVANT (EN_COURS), ajoute le 2026-08-12 : jusqu'ici, l'etat d'un
# job n'etait connu qu'APRES coup (OK/ECHEC dans l'historique). Aucun
# moyen, depuis un autre terminal pendant que l'orchestrateur tourne,
# de savoir "il en est ou la MAINTENANT". Equivalent fonctionnel du
# statut EXECUTING/ACTIVE chez Control-M/Autosys/JES : un marqueur
# .running existe UNIQUEMENT pendant l'execution reelle, contient le
# PID reel du job, et disparait des que le job se termine (succes,
# echec, ou interruption via le trap ci-dessous). Un marqueur dont le
# PID ne repond plus = execution precedente interrompue brutalement
# (crash, kill -9, coupure electrique) - jamais interprete comme "en
# cours" sans verification du PID. Voir statut_live.sh a la racine.
RUNNING_DIR="$STATE_DIR/RUNNING"
mkdir -p "$RUNNING_DIR"
ORCH_MARK="$RUNNING_DIR/_ORCHESTRATEUR.running"
echo "$(date -Iseconds),$$" > "$ORCH_MARK"
cleanup_running(){ rm -f "$ORCH_MARK" "${CURRENT_JOB_MARK:-/dev/null}" 2>/dev/null || true; }

log(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$RUN_LOG"; }
mkdir -p "$STATE_DIR/HELD"

FAILED_JOB_ID=""
FAILED_JOB_NAME=""

# Ecrit le rapport final, quelle que soit l'issue (succes, echec, Ctrl+C).
write_report() {
  {
    echo "=================================================="
    echo " RAPPORT D'EXECUTION - ${PROJECT_NAME:-WAZ_ELK_FACTORY}"
    echo "=================================================="
    echo "Date        : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Machine     : $(hostname 2>/dev/null || echo inconnue)"
    echo "ROLE        : $ROLE"
    [ "$ROLE" = "AGENT_HOST" ] && echo "Composants  : ${AGENT_COMPONENTS:-(aucun)}"
    echo "Log complet : $RUN_LOG"
    echo ""
    if [ -n "$FAILED_JOB_ID" ]; then
      echo "RESULTAT : ARRET SUR ECHEC"
      echo "Job en echec : $FAILED_JOB_ID ($FAILED_JOB_NAME)"
    else
      echo "RESULTAT : TERMINE SANS ECHEC (tous les jobs prets pour ce ROLE/composants ont ete rejoues jusqu'a stabilisation)"
    fi
    echo ""
    echo "--- JOBS TERMINES AVEC SUCCES (${STATE_DIR}/*.ok) ---"
    if ls "$STATE_DIR"/*.ok >/dev/null 2>&1; then
      ls "$STATE_DIR"/*.ok | xargs -n1 basename | sed 's/\.ok$//'
    else
      echo "(aucun)"
    fi
    echo ""
    echo "--- JOBS JAMAIS ATTEINTS (dependance non satisfaite, ou apres l'echec) ---"
    NOT_REACHED=0
    while IFS=',' read -r JOB_ID JOB_NAME JOB_ROLE COMPONENT SCRIPT_FILE DESC IN_COND OUT_COND; do
      [ "$JOB_ID" = "JOB_ID" ] && continue
      [ -z "${JOB_ID:-}" ] && continue
      [[ "$JOB_ROLE" != "$ROLE" && "$JOB_ROLE" != "ALL" ]] && continue
      if [ "$ROLE" = "AGENT_HOST" ]; then
        component_enabled "$COMPONENT" || continue
      fi
      job_done "$OUT_COND" && continue
      echo "$JOB_ID ($JOB_NAME)"
      NOT_REACHED=1
    done < "$JOBS_CSV"
    [ $NOT_REACHED -eq 0 ] && echo "(aucun - tout ce qui concerne ce ROLE/composants est termine)"
    echo "=================================================="
  } > "$REPORT_FILE"
  log "Rapport ecrit dans $REPORT_FILE"
}
trap 'cleanup_running; write_report' EXIT

log "=== Demarrage orchestrateur WAZ_ELK_FACTORY - ROLE=$ROLE - PROJET=$PROJECT_NAME ==="

if [ "$ROLE" = "ELK_HOST" ] && [ -z "${FACTORY_HOST_IP:-}" ]; then
  log "ATTENTION : FACTORY_HOST_IP est vide dans vars.conf. Certains jobs reseau (LS_008, LS_009, LS_020...) en ont besoin."
fi
if [ "$ROLE" = "AGENT_HOST" ]; then
  if [ -z "${FACTORY_HOST_IP:-}" ]; then
    log "ERREUR : FACTORY_HOST_IP doit etre renseigne dans vars.conf (IP de la VM ELK_HOST)."
  fi
  if [ -z "${AGENT_COMPONENTS:-}" ]; then
    log "ERREUR : AGENT_COMPONENTS est vide dans vars.conf. Choisissez FILEBEAT et/ou METRICBEAT et/ou WAZUH_AGENT (ex: FILEBEAT,METRICBEAT,WAZUH_AGENT)."
  else
    log "Composants actifs sur cette machine : $AGENT_COMPONENTS"
  fi
fi

MAX_PASSES=30
for pass in $(seq 1 $MAX_PASSES); do
  progressed=0
  while IFS=',' read -r JOB_ID JOB_NAME JOB_ROLE COMPONENT SCRIPT_FILE DESC IN_COND OUT_COND; do
    [ "$JOB_ID" = "JOB_ID" ] && continue
    [ -z "${JOB_ID:-}" ] && continue
    [[ "$JOB_ROLE" != "$ROLE" && "$JOB_ROLE" != "ALL" ]] && continue
    if [ "$ROLE" = "AGENT_HOST" ]; then
      component_enabled "$COMPONENT" || continue
    fi
    job_done "$OUT_COND" && continue

    ready=1
    if [ -n "$IN_COND" ] && [ "$IN_COND" != "NONE" ]; then
      IFS='|' read -ra deps <<< "$IN_COND"
      for d in "${deps[@]}"; do
        job_done "$d" || ready=0
      done
    fi
    [ $ready -eq 0 ] && continue

    # GEL MANUEL (HELD), ajoute le 2026-08-12 : un job pret (dependances
    # satisfaites) peut avoir ete explicitement gele par un operateur
    # (./geler_job.sh) - distinct d'un blocage sur dependance. On ne le
    # marque pas en echec, on ne le marque pas .ok : on le saute
    # simplement, encore et encore, tant qu'il reste gele. Voir
    # statut_live.sh pour le voir liste separement des jobs EN ATTENTE.
    if job_held "$JOB_ID"; then
      log "$JOB_ID -> GELE (HELD), saute. Liberer avec ./liberer_job.sh $JOB_ID"
      continue
    fi

    # SAUT VOLONTAIRE PAR CONFIGURATION (SKIP_JOBS), ajoute le 2026-08-14
    # (voir vars.conf et lib/commun.sh, job_in_skip_list) : decide A
    # L'AVANCE, pas une reaction a un incident - le script du job n'est
    # JAMAIS execute, sa condition est marquee satisfaite pour que la
    # suite continue, et c'est journalise de facon INDELEBILE et
    # DISTINCTE (SAUTE_CONFIG, jamais OK/ECHEC/FORCE_OK/MARQUE_FAIT).
    if job_in_skip_list "$JOB_ID"; then
      JOB_TS=$(date +%Y%m%d_%H%M%S_%N)
      mkdir -p "$HISTORY_DIR/$JOB_ID"
      JOB_LOG="$HISTORY_DIR/$JOB_ID/${JOB_TS}.log"
      {
        echo "=== SAUTE VOLONTAIREMENT (SKIP_JOBS dans vars.conf) ==="
        echo "Date/heure : $(date -Iseconds)"
        echo "Ce job n'a PAS ete execute - decide a l'avance dans vars.conf"
        echo "(SKIP_JOBS=\"$SKIP_JOBS\"), typiquement pour un creneau"
        echo "demo/test limite ou ce job est juge non bloquant pour la"
        echo "suite de la chaine. Retirez $JOB_ID de SKIP_JOBS pour qu'il"
        echo "s'execute reellement au prochain lancement."
      } > "$JOB_LOG"
      mark_done "$OUT_COND"
      echo "$(date -Iseconds),$JOB_ID,$JOB_NAME,SAUTE_CONFIG,$JOB_LOG" >> "$HISTORY_LEDGER"
      log "$JOB_ID -> SAUTE VOLONTAIREMENT (SKIP_JOBS, vars.conf) - $OUT_COND marque sans execution"
      progressed=1
      continue
    fi

    SCRIPT_PATH="$SCRIPT_DIR/jobs/$SCRIPT_FILE"
    if [ ! -f "$SCRIPT_PATH" ]; then
      log "$JOB_ID -> SCRIPT ABSENT ($SCRIPT_FILE), saute (pas encore ecrit). Voir roadmap."
      continue
    fi

    # Verification/auto-guerison /dev/null (voir lib/commun.sh) - avant
    # CHAQUE job, cout negligeable, filet de securite contre l'incident
    # reel du 2026-08-14 (SSH devenu inaccessible en cours de deploiement
    # a cause de /dev/null corrompu, sans lien avec le job en cours).
    check_dev_null

    log "--- $JOB_ID ($JOB_NAME) : $DESC ---"
    JOB_TS=$(date +%Y%m%d_%H%M%S_%N)
    mkdir -p "$HISTORY_DIR/$JOB_ID"
    JOB_LOG="$HISTORY_DIR/$JOB_ID/${JOB_TS}.log"

    # Lance en arriere-plan uniquement pour recuperer le PID reel du
    # job (necessaire pour que statut_live.sh puisse verifier si un
    # marqueur EN_COURS est encore vivant) - orchestrator.sh reste
    # sequentiel : le "wait" juste apres bloque jusqu'a la fin du job,
    # exactement comme un appel synchrone.
    # CORRIGE le 2026-09-01 (meme classe de bug diagnostiquee et corrigee
    # le meme jour sur ERP_CRM_FACTORY, code source d'origine partage
    # entre les deux projets - voir docs/JOURNAL_TECHNIQUE.md) : sans
    # "< /dev/null", le job herite du MEME descripteur stdin que la
    # boucle "while read ... done < jobs_table.csv" qui pilote
    # l'orchestrateur - si le job (ou un sous-processus qu'il lance) lit
    # ne serait-ce qu'un octet sur stdin, cet octet est vole directement
    # dans le flux du CSV en cours de lecture, decalant silencieusement
    # la position de lecture pour toutes les lignes suivantes.
    JOB_START_EPOCH=$(date +%s)
    bash "$SCRIPT_PATH" > "$JOB_LOG" 2>&1 < /dev/null &
    JOB_PID=$!
    CURRENT_JOB_MARK="$RUNNING_DIR/${JOB_ID}.running"
    echo "$(date -Iseconds),$JOB_PID,$JOB_NAME" > "$CURRENT_JOB_MARK"
    wait "$JOB_PID"
    JOB_EXIT=$?
    rm -f "$CURRENT_JOB_MARK"
    CURRENT_JOB_MARK=""
    # DUREE_SEC (ajoute le 2026-08-12) : necessaire a statut_live.sh
    # pour detecter un job EN COURS anormalement long par rapport a sa
    # moyenne historique (SLA/retard) - directement motive par
    # l'incident reel ES_027 (timeout de 5 min decouvert seulement une
    # fois termine, aucune alerte pendant qu'il tournait).
    JOB_DURATION_SEC=$(( $(date +%s) - JOB_START_EPOCH ))
    cat "$JOB_LOG" >> "$RUN_LOG"
    if [ $JOB_EXIT -eq 0 ]; then
      mark_done "$OUT_COND"
      echo "$(date -Iseconds),$JOB_ID,$JOB_NAME,OK,$JOB_LOG,$JOB_DURATION_SEC" >> "$HISTORY_LEDGER"
      log "$JOB_ID -> OK ($OUT_COND) [historique: ./historique_job.sh $JOB_ID]"
      progressed=1
    else
      echo "$(date -Iseconds),$JOB_ID,$JOB_NAME,ECHEC,$JOB_LOG,$JOB_DURATION_SEC" >> "$HISTORY_LEDGER"
      log "$JOB_ID -> ECHEC. Voir $JOB_LOG (ou $RUN_LOG). Arret orchestrateur."
      FAILED_JOB_ID="$JOB_ID"
      FAILED_JOB_NAME="$JOB_NAME"
      # Alerte email (notifier.sh, ajoute le 2026-08-12) - ne bloque et
      # ne casse JAMAIS l'orchestrateur, meme si l'envoi echoue ou si
      # NOTIF_ENABLED n'est pas configure.
      if [ -x "$SCRIPT_DIR/notifier.sh" ]; then
        "$SCRIPT_DIR/notifier.sh" "$JOB_ID" "$JOB_NAME" "ECHEC" "$JOB_LOG" >> "$RUN_LOG" 2>&1 || true
      fi
      exit 1
    fi
  done < "$JOBS_CSV"
  [ $progressed -eq 0 ] && break
done

log "=== Fin orchestrateur ==="
log "Etat final (jobs termines) :"
ls "$STATE_DIR" 2>/dev/null | grep '\.ok$' | tee -a "$RUN_LOG"
