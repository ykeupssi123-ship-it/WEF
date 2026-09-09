#!/bin/bash
# MB_016 - WEF_MB_RUN_STRESSTEST - Generation de faux pics d'activite
#
# CORRIGE LE 2026-09-09 (audit de conformite ELK_HOST/AGENT_HOST) :
# "dnf install" jamais verifie - meme classe de bug deja corrigee ce
# jour dans ES_017/KB_005/LS_011. Impact reel ici moindre (la commande
# stress-ng suivante aurait de toute facon echoue bruyamment avec
# "commande introuvable" si l'installation avait rate en silence -
# jamais un echec masque comme l'etait ES_017), mais corrige quand meme
# pour la meme discipline partout : echec de dnf visible immediatement,
# jamais suppose.
set -uo pipefail
source "$VARS_FILE"
echo "[MB_016] Generation de charge artificielle (stress-ng)..."
if ! command -v stress-ng >/dev/null; then
  if ! dnf install -y stress-ng; then
    echo "[MB_016] ERREUR : dnf install stress-ng a echoue (voir message ci-dessus)." >&2
    exit 1
  fi
fi
stress-ng --cpu 2 --vm 1 --vm-bytes 128M --timeout 15s
echo "[MB_016] OK."
exit 0
