#!/bin/bash
# bin/incident_card.sh - Consultation des fiches d'incident individuelles
# (state/incidents/<INC-ID>.txt), generees automatiquement par
# bin/incidents.sh - jamais ecrites a la main.
#
# AJOUTE LE 2026-10-18 (demande explicite : que l'exploitation, en 2045
# comme aujourd'hui, retrouve directement "la fiche devant lui" depuis
# la ligne de commande, sans devoir connaitre le mecanisme interne ni
# fouiller state/INCIDENTS.csv a la main). Cet outil ne genere RIEN -
# bin/incidents.sh reste l'unique source de verite et d'ecriture - il ne
# fait que LIRE et PRESENTER ce qui existe deja, meme discipline que
# bin/history.sh/bin/sla_report.sh vis-a-vis de JOBS_HISTORY.csv.
#
# Usage :
#   ./bin/incident_card.sh                   -> liste toutes les fiches
#   ./bin/incident_card.sh INC-0007           -> affiche la fiche complete
#   ./bin/incident_card.sh --open             -> liste uniquement OUVERT
#   ./bin/incident_card.sh --severity P1      -> liste uniquement une severite
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CARDS_DIR="$HERE/state/incidents"
REGISTRY="$HERE/state/INCIDENTS.csv"
ARG1="${1:-}"
ARG2="${2:-}"

# --- Mode affichage d'une fiche precise : INC-xxxx donne tel quel ---
if [[ "$ARG1" =~ ^INC-[0-9]+$ ]]; then
  CARD="$CARDS_DIR/${ARG1}.txt"
  if [ ! -f "$CARD" ]; then
    echo "ERREUR : fiche '$ARG1' introuvable sous $CARDS_DIR/." >&2
    echo "Utilisez './bin/incident_card.sh' sans argument pour lister les fiches existantes." >&2
    exit 1
  fi
  cat "$CARD"
  exit 0
fi

# --- Mode liste (par defaut, ou filtre --open / --severity) ---
if [ ! -f "$REGISTRY" ]; then
  echo "Aucun registre (state/INCIDENTS.csv absent) - lancez d'abord ./bin/incidents.sh."
  exit 0
fi

REGISTRY_FILE="$REGISTRY" CARDS_DIR="$CARDS_DIR" ARG1="$ARG1" ARG2="$ARG2" python3 << 'PYEOF'
import csv, os

registry_file = os.environ['REGISTRY_FILE']
cards_dir = os.environ['CARDS_DIR']
arg1 = os.environ.get('ARG1', '')
arg2 = os.environ.get('ARG2', '')

filter_statut = "OUVERT" if arg1 == "--open" else ""
filter_sev = arg2 if arg1 == "--severity" else ""

if arg1 not in ("", "--open", "--severity"):
    print(f"ERREUR : argument inconnu '{arg1}'.", file=__import__('sys').stderr)
    print("Usage : incident_card.sh [INC-xxxx | --open | --severity P1|P2|P3]", file=__import__('sys').stderr)
    raise SystemExit(1)

with open(registry_file, encoding='utf-8') as f:
    rows = list(csv.DictReader(f))

rows = [r for r in rows if (not filter_statut or r['statut'] == filter_statut)
        and (not filter_sev or r['severite'] == filter_sev)]

if not rows:
    print("Aucune fiche ne correspond a ce filtre.")
    raise SystemExit(0)

print(f"{'ID':<10} {'DETECTE LE':<20} {'JOB':<32} {'SEV':<4} {'STATUT':<8} FICHE")
print("-" * 100)
for r in rows:
    fiche = os.path.join("state/incidents", r['incident_id'] + ".txt")
    exists = "OK" if os.path.isfile(os.path.join(cards_dir, r['incident_id'] + ".txt")) else "MANQUANTE"
    print(f"{r['incident_id']:<10} {r['detecte_le']:<20} {r['job_id']:<32} {r['severite']:<4} "
          f"{r['statut']:<8} {fiche} ({exists})")

print()
print(f"{len(rows)} incident(s) affiche(s). Fiche complete : ./bin/incident_card.sh <ID>")
PYEOF
