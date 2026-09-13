#!/bin/bash
# sync_branch.sh - synchronise la branche courante avec origin en UNE
# commande, meme quand git signale des "branches divergentes" (VM1 a
# souvent des commits locaux issus de resolutions de conflit faites
# directement sur la machine). Ajoute le 2026-09-13 apres plusieurs
# soirs a retaper a la main "git merge origin/<branche>" puis le sed
# de nettoyage des marqueurs de conflit dans docs/JOURNAL_TECHNIQUE.md.
#
# Ce script ne resout AUTOMATIQUEMENT que le cas deja rencontre et
# documente : un conflit portant UNIQUEMENT sur docs/JOURNAL_TECHNIQUE.md
# (les deux cotes ne font qu'ajouter des entrees datees distinctes, donc
# supprimer les marqueurs <<<<<<< / ======= / >>>>>>> est toujours sur).
# Si un autre fichier est en conflit, le script s'arrete et rend la main
# - jamais de resolution automatique aveugle sur un fichier de code.
#
# Usage :
#   ./bin/sync_branch.sh                -> synchronise la branche courante
#   ./bin/sync_branch.sh <nom-branche>  -> bascule dessus puis synchronise
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE" || exit 1

BRANCH="${1:-$(git rev-parse --abbrev-ref HEAD)}"

echo "[sync_branch] git fetch origin..."
git fetch origin || { echo "[sync_branch] ERREUR : fetch a echoue."; exit 1; }

echo "[sync_branch] Bascule sur '$BRANCH'..."
git checkout "$BRANCH" || { echo "[sync_branch] ERREUR : impossible de basculer sur '$BRANCH'."; exit 1; }

if git merge "origin/$BRANCH" --no-edit; then
  echo "[sync_branch] OK, deja a jour ou fusion automatique reussie."
  exit 0
fi

CONFLICTS="$(git diff --name-only --diff-filter=U)"
if [ "$CONFLICTS" = "docs/JOURNAL_TECHNIQUE.md" ]; then
  echo "[sync_branch] Conflit attendu sur docs/JOURNAL_TECHNIQUE.md (entrees ajoutees des deux cotes), resolution automatique..."
  sed -i '/^<<<<<<< /d; /^=======$/d; /^>>>>>>> /d' docs/JOURNAL_TECHNIQUE.md
  git add docs/JOURNAL_TECHNIQUE.md
  git commit --no-edit
  echo "[sync_branch] OK, conflit resolu et fusionne."
  exit 0
fi

echo "[sync_branch] ERREUR : conflit sur un fichier non couvert par la resolution automatique :"
echo "$CONFLICTS"
echo "[sync_branch] Fusion laissee en l'etat, resolvez manuellement puis 'git commit'."
exit 1
