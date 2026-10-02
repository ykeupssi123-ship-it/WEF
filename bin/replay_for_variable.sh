#!/bin/bash
# bin/replay_for_variable.sh - AJOUTE LE 2026-10-02, demande explicite :
# certaines variables de vars.conf sont consommees par un grand nombre de
# jobs (de 3 a 48, verifie reellement) - rejouer chacun a la main via
# bin/order.sh exigerait une confirmation tapee PAR job, et aucune garantie
# de les jouer dans le bon ordre de dependance. Ce script rejoue EXACTEMENT
# les jobs qui consomment une variable donnee, jamais plus, jamais moins
# (meme recherche reelle que vars_pilotage_analysis.py, voir
# lib/consumers_for_variable.py), dans un ordre de dependance reel calcule
# sur IN_COND/OUT_COND, avec UNE SEULE confirmation pour tout le lot - pas
# une par job - et un compte-rendu clair job par job.
#
# Discipline reprise a l'identique de bin/order.sh (jamais reinventee) :
#   - une RAISON est obligatoire (meme regle d'audit) ;
#   - refuse si au moins un job du lot est GELE (HELD) - un gel reste une
#     decision deliberee, jamais court-circuitee par ce chemin non plus ;
#   - UNE entree CHANGE_LOG.csv par job tente, meme format que order.sh ;
#   - verrou d'execution unique pour tout le lot (acquire_run_lock), pris
#     APRES la confirmation tapee, jamais avant (meme raison que order.sh :
#     ne jamais bloquer bin/scheduler.sh pendant qu'un humain reflechit) ;
#   - execution reelle via lib/run_job.sh (meme mecanique que l'orchestrateur
#     normal et que order.sh - marqueur .ok, historique, dechiffrement de
#     jobs.enc/ si present), labels REPLAY_OK/REPLAY_ECHEC (jamais confondus
#     avec OK/ECHEC normal ni avec FORCE_OK/FORCE_ECHEC d'un forcage
#     individuel) ;
#   - ARRET immediat au premier echec : un job plus loin dans le lot peut
#     dependre reellement de celui qui vient d'echouer (c'est precisement
#     ce que le tri topologique vient de garantir) - continuer quand meme
#     rejouerait des jobs sur une base fausse. Les jobs non encore tentes
#     sont listes explicitement comme NON TENTES, jamais confondus avec un
#     echec ou un succes.
#
# Usage :
#   ./bin/replay_for_variable.sh <NOM_VARIABLE> "<raison>"
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -d "$HERE/.git" ] && [ -x "$HERE/bin/sync_branch.sh" ]; then
  echo "[auto-sync] Synchronisation de la branche courante avec origin..."
  if ! "$HERE/bin/sync_branch.sh"; then
    if git -C "$HERE" status --porcelain 2>/dev/null | grep -q '^UU'; then
      echo "[auto-sync] ERREUR : conflit de fusion non resolu - resolvez manuellement avant de relancer." >&2
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
check_config_drift

VARNAME="${1:-}"
RAISON="${2:-}"
if [ -z "$VARNAME" ] || [ -z "$RAISON" ]; then
  echo "Usage : ./bin/replay_for_variable.sh <NOM_VARIABLE> \"<raison>\""
  echo "La raison est obligatoire (meme regle d'audit que bin/order.sh)."
  exit 1
fi
RAISON_SAFE="${RAISON//,/;}"
OPERATEUR="$(whoami)@$(hostname 2>/dev/null || echo host-inconnu)"

JOBS_CSV="$HERE/jobs_table.csv"
HISTORY_DIR="$STATE_DIR/history"
HISTORY_LEDGER="$STATE_DIR/JOBS_HISTORY.csv"
RUNNING_DIR="$STATE_DIR/RUNNING"
CHANGE_LOG="${STATE_DIR}/CHANGE_LOG.csv"
mkdir -p "$HISTORY_DIR" "$RUNNING_DIR" "$WORK_TMP_DIR"
[ -f "$HISTORY_LEDGER" ] || echo "TIMESTAMP,JOB_ID,JOB_NAME,RESULT,LOG_FILE" > "$HISTORY_LEDGER"
[ -f "$CHANGE_LOG" ] || printf '"timestamp","job_id","operateur","raison","niveau_risque","dependances_manquantes","impact_aval","resultat"\n' > "$CHANGE_LOG"

# Recherche reelle (jamais une liste a la main) + tri de dependance reel -
# voir lib/consumers_for_variable.py pour le detail des deux etapes.
ORDERED_JOBS=()
CONSUMER_OUT="$(python3 "$HERE/lib/consumers_for_variable.py" "$VARNAME")"
CONSUMER_RC=$?
if [ "$CONSUMER_RC" -eq 2 ]; then
  echo "Aucun job de cette usine ne consomme $VARNAME (verifie par recherche reelle dans le code)."
  echo "Si cette variable est pilotee hors du systeme de jobs (bin/, setup/, lib/), voir la"
  echo "colonne 'Rejeu / verification' de la feuille 4 du tableur pour la commande reelle."
  exit 2
elif [ "$CONSUMER_RC" -ne 0 ]; then
  echo "ERREUR lors de la recherche des jobs dependants (voir message ci-dessus)." >&2
  exit 1
fi
# CORRIGE LE 2026-10-02 (meme incident reel que le CONFIRM de bin/order.sh :
# "retour chariot invisible (\r), frequent via certains clients terminal /
# Python sous Windows en mode texte") - sans ce nettoyage, chaque JOB_ID
# porte un \r invisible en fin de chaine, et plus aucun "grep ^${j}," ne
# retrouve jamais la ligne correspondante dans jobs_table.csv plus bas.
while IFS= read -r line; do
  line="${line%$'\r'}"
  [ -n "$line" ] && ORDERED_JOBS+=("$line")
done <<< "$CONSUMER_OUT"

# CORRIGE LE 2026-10-02 (trouve en verifiant un cas reel a 10 jobs avant
# de le montrer : APP_BIN est consomme par des jobs des DEUX roles,
# AGENT_HOST et ELK_HOST - exactement le meme filtre que orchestrator.sh
# (ligne "JOB_ROLE != ROLE && JOB_ROLE != ALL => continue"), jamais
# applique jusqu'ici par ce script ni par bin/order.sh lui-meme. Sans ce
# filtre, lancer ce script sur UNE machine tenterait aussi les jobs de
# L'AUTRE machine - au mieux un echec immediat (service absent), au pire
# une action reelle sur la mauvaise cible (purge, etc.). Separe le lot en
# "pour cette machine" (ROLE ou ALL) et "pour l'autre role" (affiche,
# jamais tente, jamais compte comme echec).
RUNNABLE_HERE=()
OTHER_ROLE=()
for j in "${ORDERED_JOBS[@]}"; do
  j_role="$(awk -F',' -v id="$j" '$1==id{print $3}' "$JOBS_CSV")"
  if [ "$j_role" = "$ROLE" ] || [ "$j_role" = "ALL" ]; then
    RUNNABLE_HERE+=("$j")
  else
    OTHER_ROLE+=("$j ($j_role)")
  fi
done
ORDERED_JOBS=("${RUNNABLE_HERE[@]}")

# AJOUTE LE 2026-10-02, demande explicite : le bilan complet d'un rejeu de
# lot (liste ordonnee, jobs exclus par role, confirmation, resultat final)
# ne vivait jusqu'ici que dans le terminal - perdu des que la fenetre se
# ferme, alors que chaque job INDIVIDUEL a deja son propre log persistant
# (state/history/<JOB_ID>/<horodatage>.log). Meme principe applique ici au
# niveau du LOT entier, jamais un nouveau format invente : un fichier par
# execution de ce script, dans le meme repertoire state/history/.
#
# CORRIGE LE 2026-10-02 (teste reellement avant de pousser, jamais suppose
# suffisant) : la premiere version utilisait "exec > >(tee -a ...) 2>&1"
# puis "wait" sur le PID du tee en sortie - motif courant sous Linux, mais
# BLOQUE INDEFINIMENT lors du test reel dans cet environnement (process
# substitution geree differemment). Remplace par un motif plus simple et
# plus portable : tout le reste du script (jusqu'a la fin) est enveloppe
# dans un bloc "{ ... } | tee -a fichier" - aucun PID a suivre, aucune
# race possible (le pipe reste ouvert tant que le bloc ecrit, tee ne voit
# EOF qu'apres la derniere ligne). "set -o pipefail" (deja actif en tete
# de ce script) fait remonter le vrai code de sortie du bloc a travers le
# tee - verifie reellement : un "exit 3" dans le bloc ressort bien comme
# code 3 apres le pipe, jamais celui de tee.
REPLAY_BATCH_DIR="$STATE_DIR/history/_replay_batches"
mkdir -p "$REPLAY_BATCH_DIR"
BATCH_TS=$(date +%Y%m%d_%H%M%S)
BATCH_LOG="$REPLAY_BATCH_DIR/${VARNAME}_${BATCH_TS}.log"
{

echo "=================================================="
echo " REJEU CIBLE - variable $VARNAME"
echo "=================================================="
echo "Operateur      : $OPERATEUR"
echo "Cette machine  : ROLE=$ROLE"
echo "Raison         : $RAISON_SAFE"
echo "Journal de ce lot (ce bilan complet, archive) : $BATCH_LOG"
echo ""
echo "${#ORDERED_JOBS[@]} job(s) consomment reellement $VARNAME ET s'executent sur CETTE machine"
echo "(recherche reelle, ordre de dependance reel calcule sur IN_COND/OUT_COND) :"
i=0
for j in "${ORDERED_JOBS[@]}"; do
  i=$((i+1))
  echo "  $i. $j"
done
if [ "${#OTHER_ROLE[@]}" -gt 0 ]; then
  echo ""
  echo "${#OTHER_ROLE[@]} job(s) consomment aussi $VARNAME mais appartiennent a l'AUTRE role -"
  echo "jamais tentes depuis cette machine, a rejouer depuis la machine concernee :"
  for j in "${OTHER_ROLE[@]}"; do
    echo "  - $j"
  done
fi
if [ "${#ORDERED_JOBS[@]}" -eq 0 ]; then
  echo ""
  echo "Aucun job pour le role de cette machine ($ROLE) - rien a faire ici pour $VARNAME."
  exit 2
fi
echo ""

HELD_JOBS=()
for j in "${ORDERED_JOBS[@]}"; do
  job_held "$j" && HELD_JOBS+=("$j")
done
if [ "${#HELD_JOBS[@]}" -gt 0 ]; then
  echo "ERREUR : le(s) job(s) suivant(s) sont explicitement GELE(S) (HELD) : ${HELD_JOBS[*]}"
  echo "Un gel est une decision d'exploitation deliberee - elle ne peut pas etre court-circuitee"
  echo "par ce rejeu groupe non plus. Liberez-les d'abord (bin/free.sh) si voulu, ou retirez-les"
  echo "de ce lot en les gelant volontairement ailleurs."
  exit 1
fi

if [ ! -t 0 ]; then
  echo "ERREUR : confirmation interactive requise (pas de terminal attache)." >&2
  exit 1
fi
read -r -p "Tapez exactement '$VARNAME' pour confirmer le rejeu de ces ${#ORDERED_JOBS[@]} job(s) : " CONFIRM
CONFIRM="${CONFIRM%$'\r'}"
# Le terminal de l'operateur affiche deja ce qu'il tape (echo local du TTY),
# mais ce texte ne passe jamais par le stdout/stderr DE CE SCRIPT - donc
# jamais capture par le "tee" ci-dessus sans cette ligne explicite.
echo "Confirmation saisie : $CONFIRM"
if [ "$CONFIRM" != "$VARNAME" ]; then
  echo "Confirmation incorrecte. Rejeu annule, rien n'a ete execute."
  exit 1
fi

if ! acquire_run_lock "replay_for_variable.sh:$VARNAME par $OPERATEUR" 5; then
  echo "ERREUR : une autre execution WEF est en cours sur cette machine (voir $STATE_DIR/.wef_run.owner). Reessayez dans quelques instants." >&2
  exit 1
fi
trap release_run_lock EXIT

declare -A RESULT
declare -A RESULT_LOG
ATTEMPTED=()
STOPPED_AT=""
for j in "${ORDERED_JOBS[@]}"; do
  LINE=""
  while IFS=',' read -r C_JOB_ID C_JOB_NAME C_JOB_ROLE C_COMPONENT C_SCRIPT_FILE C_DESC C_IN_COND C_OUT_COND; do
    [ "$C_JOB_ID" = "$j" ] && { LINE=1; break; }
  done < "$JOBS_CSV"
  if [ -z "$LINE" ]; then
    echo "ERREUR : $j introuvable dans jobs_table.csv (incoherence entre la recherche et le referentiel - jamais vu jusqu'ici)." >&2
    RESULT["$j"]="INTROUVABLE"
    STOPPED_AT="$j"
    break
  fi

  SCRIPT_PATH="$HERE/jobs/$C_SCRIPT_FILE"
  if [ ! -f "$SCRIPT_PATH" ]; then
    echo "ERREUR : script $SCRIPT_PATH introuvable pour $j." >&2
    RESULT["$j"]="INTROUVABLE"
    STOPPED_AT="$j"
    break
  fi

  ATTEMPTED+=("$j")
  JOB_TS=$(date +%Y%m%d_%H%M%S_%N)
  mkdir -p "$HISTORY_DIR/$j"
  JOB_LOG="$HISTORY_DIR/$j/${JOB_TS}.log"
  {
    echo "=== REJEU CIBLE PAR VARIABLE ($VARNAME) ==="
    echo "Operateur   : $OPERATEUR"
    echo "Date/heure  : $(date -Iseconds)"
    echo "Raison      : $RAISON_SAFE"
    echo "Position dans le lot : $j (${#ATTEMPTED[@]}/${#ORDERED_JOBS[@]})"
    echo "=== Sortie reelle du job ==="
  } > "$JOB_LOG"

  echo ""
  echo ">>> Rejeu de $j (${#ATTEMPTED[@]}/${#ORDERED_JOBS[@]})..."
  run_job "$j" "$C_JOB_NAME (REPLAY $VARNAME)" "$SCRIPT_PATH" "$JOB_LOG" "$C_OUT_COND" "REPLAY_OK" "REPLAY_ECHEC"
  JOB_EXIT=$?

  CHANGE_RESULT="ECHEC"; [ "$JOB_EXIT" -eq 0 ] && CHANGE_RESULT="OK"
  printf '"%s","%s","%s","%s","%s","%s","%s","%s"\n' \
    "$(date -Iseconds)" "$j" "$OPERATEUR" "${RAISON_SAFE//\"/\'} (lot $VARNAME)" "MOYEN" "aucune" "aucun" "$CHANGE_RESULT" >> "$CHANGE_LOG"

  RESULT_LOG["$j"]="$JOB_LOG"
  if [ "$JOB_EXIT" -eq 0 ]; then
    RESULT["$j"]="OK"
    echo "<<< $j -> REPLAY_OK."
  else
    RESULT["$j"]="ECHEC"
    echo "<<< $j -> REPLAY_ECHEC. Voir $JOB_LOG."
    STOPPED_AT="$j"
    if [ -x "$HERE/bin/notify.sh" ]; then
      "$HERE/bin/notify.sh" "$j" "$C_JOB_NAME (REJEU CIBLE $VARNAME)" "REPLAY_ECHEC" "$JOB_LOG" || true
    fi
    break
  fi
done

echo ""
echo "=================================================="
echo " BILAN - rejeu de $VARNAME"
echo "=================================================="
# AJOUTE LE 2026-10-02, demande explicite : une liste en prose se lit mal
# des que le lot depasse quelques jobs (imagine pour 50) - jamais un
# format invente ici, repris tel quel du tableau deja utilise par
# bin/audit.sh (memes printf "%-Ns", meme ligne de tirets) pour rester
# coherent avec le reste du projet. Une seule ligne meme pour un lot d'UN
# seul job. Le marqueur "!!" en tete des lignes non-OK permet de reperer
# un echec/non-tente sans avoir a lire chaque ligne une par une, meme en
# conservant l'ordre reel d'execution (jamais trie a part, cet ordre EST
# l'information : il montre jusqu'ou la chaine est allee).
NOT_ATTEMPTED=()
printf "%-3s %-3s %-11s %-32s %s\n" "" "#" "STATUT" "JOB_ID" "LOG"
printf "%-3s %-3s %-11s %-32s %s\n" "" "---" "-----------" "--------------------------------" "---"
i=0
# CORRIGE LE 2026-10-02 (teste reellement avant de pousser) : deux boucles
# separees (jobs avec resultat, puis NOT_ATTEMPTED) incrementaient TOUTES
# LES DEUX "i" pour le meme job quand il n'avait pas encore de resultat -
# le numero de ligne sautait (3 puis 5, jamais 4). Une seule boucle,
# jamais deux compteurs qui se marchent dessus.
for j in "${ORDERED_JOBS[@]}"; do
  i=$((i+1))
  if [ -n "${RESULT[$j]:-}" ]; then
    MARK=""; [ "${RESULT[$j]}" != "OK" ] && MARK="!!"
    printf "%-3s %-3s %-11s %-32s %s\n" "$MARK" "$i" "${RESULT[$j]}" "$j" "${RESULT_LOG[$j]:-}"
  else
    NOT_ATTEMPTED+=("$j")
    printf "%-3s %-3s %-11s %-32s %s\n" "!!" "$i" "NON_TENTE" "$j" "-"
  fi
done

if [ -n "$STOPPED_AT" ]; then
  echo ""
  echo "Arret apres l'echec de $STOPPED_AT - ${#NOT_ATTEMPTED[@]} job(s) non tente(s) listes ci-dessus"
  echo "(un job plus loin dans ce lot peut dependre reellement de celui qui vient d'echouer)."
  exit 1
fi
echo ""
echo "Tous les jobs du lot ont reussi (${#ORDERED_JOBS[@]}/${#ORDERED_JOBS[@]})."
exit 0

} 2>&1 | tee -a "$BATCH_LOG"
# CORRIGE LE 2026-10-02 (incident reel signale par l'operateur : le
# contexte - en-tete, liste des jobs - s'affichait APRES l'invite de
# confirmation, jamais avant, dans un rejeu reel sur wef-elk-core).
# CAUSE REELLE : "read -p" ecrit son invite sur STDERR (comportement
# documente de bash), jamais sur stdout - sans ce "2>&1" AVANT le pipe,
# stdout (les echo du bilan) et stderr (l'invite) empruntaient deux
# chemins separes vers le terminal, sans ordre garanti entre les deux ;
# stderr arrivait plus vite, affichant l'invite SEULE, sans aucun contexte
# - un operateur pourrait alors confirmer un rejeu destructeur sans avoir
# vu ce qu'il confirme reellement. Fusionner stderr dans stdout AVANT le
# pipe force un seul flux serialise, ordre garanti, jamais plus de course
# possible entre les deux. Benefice secondaire : l'invite elle-meme est
# desormais aussi archivee dans le fichier de lot.
# "set -o pipefail" (deja actif, voir "set -uo pipefail" en tete de ce
# script) fait remonter ici le vrai code de sortie du bloc ci-dessus,
# jamais celui de tee - verifie reellement avant de pousser (voir le
# commentaire plus haut, au point ou $BATCH_LOG est defini).
exit $?
