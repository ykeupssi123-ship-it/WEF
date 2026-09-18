#!/bin/bash
# bin/order.sh - Force Start manuel d'un job, ajoute le 2026-08-12.
# Equivalent fonctionnel de l'action "Force" d'un ordonnanceur type
# Control-M/Autosys/JES : demarre un job precis MEME SI ses dependances
# (IN_COND) ne sont pas satisfaites - operation volontairement rare et
# risquee (l'operateur prend la responsabilite que c'est correct de le
# faire malgre tout), jamais silencieuse :
#   - affiche explicitement ce qui manque avant de demander confirmation ;
#   - exige de retaper le JOB_ID exact (pas juste "oui/y") ;
#   - refuse de forcer un job explicitement GELE (HELD) - un gel est une
#     decision d'exploitation deliberee, elle ne doit jamais pouvoir
#     etre court-circuitee par megarde : il faut d'abord bin/free.sh ;
#   - exige une RAISON (audit bancaire : aucune derogation manuelle sans
#     justification nominative) - capturee avec l'identite de
#     l'operateur (whoami@hostname) EN TETE du log dedie de cette
#     execution (equivalent SYSOUT), pas dans le registre CSV (qui reste
#     un simple index, jamais un endroit ou stocker du texte libre) ;
#   - passe par EXACTEMENT le meme mecanisme d'historique/marqueur
#     EN_COURS que l'orchestrateur normal (state/history/<JOB_ID>/...,
#     state/RUNNING/<JOB_ID>.running) ;
#   - mais est marque de facon INDELEBILE et DISTINCTE dans le registre
#     (FORCE_OK / FORCE_ECHEC, jamais OK/ECHEC tout court) pour qu'un
#     audit ulterieur sache TOUJOURS qu'un humain a court-circuite le
#     controle de dependances a ce moment precis, meme si le job a
#     reussi.
#
# Usage :
#   ./bin/order.sh <JOB_ID> "<raison>"
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# AJOUTE LE 2026-09-14 (demande explicite : "je souhaiterais qu'a la
# longue on ne soit plus a taper ce genre de chose (sync_branch.sh)") -
# synchronise automatiquement la branche courante avec origin AVANT de
# LIRE VARS_FILE/jobs_table.csv (deliberement place avant le "source"
# ci-dessous - CORRIGE LE 2026-09-14, incident reel : place initialement
# APRES "source $VARS_FILE", REPEATABLE_JOBS restait donc celui d'AVANT
# la synchronisation au tout premier lancement suivant une mise a jour,
# le rendant inoperant sans qu'aucune erreur ne le signale - jamais un
# second essai ne devrait etre necessaire). Best-effort : l'absence de
# reseau ne bloque jamais un run local (avertissement, puis poursuite
# avec le code existant) - seul un VRAI conflit de fusion non resolu
# arrete le script, car jobs_table.csv pourrait sinon contenir des
# marqueurs de conflit et casser silencieusement toute la resolution de
# dependances.
if [ -d "$HERE/.git" ] && [ -x "$HERE/bin/sync_branch.sh" ]; then
  echo "[auto-sync] Synchronisation de la branche courante avec origin..."
  if ! "$HERE/bin/sync_branch.sh"; then
    if git -C "$HERE" status --porcelain 2>/dev/null | grep -q '^UU'; then
      echo "[auto-sync] ERREUR : conflit de fusion non resolu (fichier(s) en UU) - jobs_table.csv ou un job pourrait etre corrompu. Resolvez manuellement (git status) avant de relancer." >&2
      exit 1
    fi
    echo "[auto-sync] ATTENTION : synchronisation impossible (reseau absent ?) - poursuite avec le code local existant." >&2
  fi
fi

export VARS_FILE="${VARS_FILE:-$HERE/vars.conf}"
source "$VARS_FILE"
source "$HERE/lib/commun.sh"
source "$HERE/lib/run_job.sh"
source "$HERE/lib/lock.sh"

JOB_ID="${1:-}"
RAISON="${2:-}"
if [ -z "$JOB_ID" ] || [ -z "$RAISON" ]; then
  echo "Usage : ./bin/order.sh <JOB_ID> \"<raison>\""
  echo "La raison est obligatoire (audit - on ne force jamais un job sans dire pourquoi)."
  echo "Voir ./bin/monitor.sh pour la liste des jobs EN ATTENTE forcable."
  exit 1
fi
RAISON_SAFE="${RAISON//,/;}"
OPERATEUR="$(whoami)@$(hostname 2>/dev/null || echo host-inconnu)"

JOBS_CSV="$HERE/jobs_table.csv"
HISTORY_DIR="$STATE_DIR/history"
HISTORY_LEDGER="$STATE_DIR/JOBS_HISTORY.csv"
RUNNING_DIR="$STATE_DIR/RUNNING"
mkdir -p "$HISTORY_DIR" "$RUNNING_DIR" "$WORK_TMP_DIR"
[ -f "$HISTORY_LEDGER" ] || echo "TIMESTAMP,JOB_ID,JOB_NAME,RESULT,LOG_FILE" > "$HISTORY_LEDGER"

LINE=""
while IFS=',' read -r C_JOB_ID C_JOB_NAME C_JOB_ROLE C_COMPONENT C_SCRIPT_FILE C_DESC C_IN_COND C_OUT_COND; do
  [ "$C_JOB_ID" = "$JOB_ID" ] && { LINE=1; break; }
done < "$JOBS_CSV"

if [ -z "$LINE" ]; then
  CURRENT_BRANCH="$(git -C "$HERE" branch --show-current 2>/dev/null || echo inconnue)"
  echo "ERREUR : $JOB_ID introuvable dans jobs_table.csv (branche actuelle : $CURRENT_BRANCH)."
  # AJOUTE LE 2026-09-14 (demande explicite : "plus jamais des soucis
  # avec ca, qu'on n'en parle plus jamais") - incident reel recurrent
  # ce soir : un job existe bien, mais sur une AUTRE branche que celle
  # actuellement extraite (ex: BEAC_003 existe sur demo-donnees-realistes,
  # jamais sur main) - le message "introuvable" seul ne dit jamais
  # POURQUOI, ni quoi faire. Cherche le job sur toutes les branches
  # locales et distantes connues et l'indique explicitement.
  if [ -d "$HERE/.git" ]; then
    FOUND_ON=""
    for b in $(git -C "$HERE" for-each-ref --format='%(refname:short)' refs/heads/ refs/remotes/origin/ 2>/dev/null | sed 's#^origin/##' | sort -u); do
      [ "$b" = "HEAD" ] && continue
      if git -C "$HERE" show "$b:jobs_table.csv" 2>/dev/null | grep -q "^${JOB_ID},"; then
        FOUND_ON="${FOUND_ON}${FOUND_ON:+ }$b"
      fi
    done
    if [ -n "$FOUND_ON" ]; then
      echo "Ce job existe sur : ${FOUND_ON} - pas sur '${CURRENT_BRANCH}'."
      echo "Basculez dessus puis reessayez :"
      for b in $FOUND_ON; do
        [ "$b" != "$CURRENT_BRANCH" ] && echo "  git checkout $b && ./bin/sync_branch.sh $b"
      done
    else
      echo "Introuvable sur aucune branche connue (locale ou distante) - verifiez l'orthographe exacte du JOB_ID."
    fi
  fi
  exit 1
fi

if job_held "$JOB_ID"; then
  echo "ERREUR : $JOB_ID est explicitement GELE (HELD) :"
  cat "$STATE_DIR/HELD/${JOB_ID}.held"
  echo ""
  echo "Un gel est une decision d'exploitation deliberee - elle ne peut pas"
  echo "etre court-circuitee par un forcage. Liberez-le d'abord si voulu :"
  echo "./bin/free.sh $JOB_ID"
  exit 1
fi

# Rejeu standard pour tout job (jamais de suppression manuelle de .ok) :
# le rayon d'impact reel est calcule et affiche plus bas, la confirmation
# tapee existante fait office de validation.
ALREADY_DONE=0
ALREADY_DONE_DATE=""
IMPACT=""
if [ "$C_OUT_COND" != "NONE" ] && job_done "$C_OUT_COND"; then
  ALREADY_DONE=1
  ALREADY_DONE_DATE="$(cat "$STATE_DIR/$C_OUT_COND.ok" 2>/dev/null || echo inconnue)"
  IMPACT="$(awk -F',' -v cond="$C_OUT_COND" -v self="$JOB_ID" '
    $1 != self && $1 != "JOB_ID" {
      n = split($7, deps, "|")
      for (i=1;i<=n;i++) if (deps[i] == cond) { print $1 }
    }
  ' "$JOBS_CSV" | paste -sd, -)"
fi

MISSING=""
if [ -n "$C_IN_COND" ] && [ "$C_IN_COND" != "NONE" ]; then
  IFS='|' read -ra deps <<< "$C_IN_COND"
  for d in "${deps[@]}"; do
    job_done "$d" || MISSING="${MISSING}${MISSING:+, }$d"
  done
fi

echo "=================================================="
echo " FORCE START - $JOB_ID ($C_JOB_NAME)"
echo "=================================================="
echo "$C_DESC"
echo ""
echo "Operateur : $OPERATEUR"
echo "Raison    : $RAISON_SAFE"
echo ""
if [ -n "$MISSING" ]; then
  echo "ATTENTION : dependance(s) NON satisfaite(s) : $MISSING"
  echo "Vous vous apprêtez a forcer ce job MALGRE ces conditions manquantes."
  echo "C'est a vous de savoir si c'est correct de le faire (ex: condition"
  echo "remplie manuellement en dehors de l'orchestrateur)."
else
  echo "(Toutes les dependances sont deja satisfaites - ce job aurait de"
  echo "toute facon ete joue au prochain ./orchestrator.sh. Forcage sans risque"
  echo "particulier lie aux dependances.)"
fi
if [ "$ALREADY_DONE" -eq 1 ]; then
  echo ""
  echo "ATTENTION : ce job a deja reussi le ${ALREADY_DONE_DATE} ($C_OUT_COND deja remplie). Vous allez le REJOUER."
  if [ -n "$IMPACT" ]; then
    echo "Job(s) qui en dependent : $IMPACT - un rejeu de ceux-la aussi peut etre necessaire."
  else
    echo "Aucun autre job n'en depend - rejeu sans impact ailleurs dans la chaine."
  fi
fi
echo ""
if [ ! -t 0 ]; then
  echo "ERREUR : confirmation interactive requise (pas de terminal attache)." >&2
  exit 1
fi
read -r -p "Tapez exactement '$JOB_ID' pour confirmer le forcage : " CONFIRM
# CORRIGE LE 2026-09-13 (incident reel : JOB_ID retape a l'identique,
# refuse quand meme) - meme cause reelle que setup/MNT_reinstall.sh, un
# retour chariot invisible (\r, frequent via certains clients terminal)
# rendait "$CONFIRM" different du JOB_ID a l'octet pres, sans que rien
# ne le laisse voir a l'ecran. Nettoye avant comparaison.
CONFIRM="${CONFIRM%$'\r'}"
if [ "$CONFIRM" != "$JOB_ID" ]; then
  echo "Confirmation incorrecte. Forcage annule, rien n'a ete execute."
  exit 1
fi

# AJOUTE LE 2026-09-18 (systeme de calendrier) : le verrou est pris APRES
# la confirmation tapee, jamais avant - l'attente d'un humain au prompt
# ne doit jamais retenir le verrou (bin/scheduler.sh pourrait sinon
# rester bloque tout un tick a cause d'un operateur qui reflechit).
if ! acquire_run_lock "order.sh:$JOB_ID (FORCE) par $OPERATEUR" 5; then
  echo "ERREUR : une autre execution WEF est en cours sur cette machine (voir $STATE_DIR/.wef_run.owner). Reessayez dans quelques instants." >&2
  exit 1
fi
trap release_run_lock EXIT

if [ "$ALREADY_DONE" -eq 1 ]; then
  rm -f "$STATE_DIR/$C_OUT_COND.ok"
fi

SCRIPT_PATH="$HERE/jobs/$C_SCRIPT_FILE"
if [ ! -f "$SCRIPT_PATH" ]; then
  echo "ERREUR : script $SCRIPT_PATH introuvable."
  exit 1
fi

JOB_TS=$(date +%Y%m%d_%H%M%S_%N)
mkdir -p "$HISTORY_DIR/$JOB_ID"
JOB_LOG="$HISTORY_DIR/$JOB_ID/${JOB_TS}.log"

# En-tete d'audit AVANT la sortie reelle du job (equivalent SYSOUT) :
# c'est ici, dans le log dedie a CETTE execution, que vivent l'identite
# de l'operateur et la raison - jamais dans le registre CSV.
{
  echo "=== FORCAGE MANUEL (Force Start) ==="
  echo "Operateur   : $OPERATEUR"
  echo "Date/heure  : $(date -Iseconds)"
  echo "Raison      : $RAISON_SAFE"
  echo "Dependance(s) non satisfaite(s) au moment du forcage : ${MISSING:-aucune}"
  [ "$ALREADY_DONE" -eq 1 ] && echo "Rejeu d'un job deja reussi le ${ALREADY_DONE_DATE} ($C_OUT_COND)."
  echo "=== Sortie reelle du job ==="
} > "$JOB_LOG"

# AJOUTE LE 2026-09-18 : le lancement/l'attente/le marqueur .ok/la ligne
# d'historique vivent desormais dans lib/run_job.sh (partages avec
# orchestrator.sh et bin/scheduler.sh) - comportement inchange (PID
# capture, "< /dev/null", DUREE_SEC). Seul detail cosmetique deliberement
# simplifie : le marqueur EN_COURS portait auparavant le suffixe
# " (FORCE)" alors que la ligne d'historique restait sans suffixe - les
# deux portent desormais le meme nom (le label FORCE_OK/FORCE_ECHEC,
# inchange, reste la VRAIE preuve d'audit d'un forcage, jamais ce
# suffixe cosmetique).
run_job "$JOB_ID" "$C_JOB_NAME (FORCE)" "$SCRIPT_PATH" "$JOB_LOG" "$C_OUT_COND" "FORCE_OK" "FORCE_ECHEC"
JOB_EXIT=$?

echo "--- Sortie de $JOB_ID ---"
cat "$JOB_LOG"
echo "--- Fin de sortie ---"

if [ $JOB_EXIT -eq 0 ]; then
  echo "$JOB_ID -> FORCE_OK ($C_OUT_COND). Marque distinctement dans l'historique"
  echo "(jamais confondu avec une execution normale) : ./bin/history.sh $JOB_ID"
  exit 0
else
  echo "$JOB_ID -> FORCE_ECHEC. Voir $JOB_LOG."
  if [ -x "$HERE/bin/notify.sh" ]; then
    if [ "$ALREADY_DONE" -eq 1 ]; then
      "$HERE/bin/notify.sh" "$JOB_ID" "$C_JOB_NAME (FORCAGE MANUEL - REGRESSION, etait deja reussi)" "FORCE_ECHEC" "$JOB_LOG" || true
    else
      "$HERE/bin/notify.sh" "$JOB_ID" "$C_JOB_NAME (FORCAGE MANUEL)" "FORCE_ECHEC" "$JOB_LOG" || true
    fi
  fi
  exit 1
fi
