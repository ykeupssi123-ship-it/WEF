#!/bin/bash
# WAZ_022 - WEF_WAZ_BLD_APIKEYGEN - Token d'interconnexion API Wazuh
#
# MODIFIE LE 2026-08-30 : WAZ_API_PASSWORD vient desormais de
# WAZ_API_PASSWORD_FILE (jamais vars.conf en clair). Lu en LECTURE SEULE
# (generer=non) : contrairement a WAZ_INDEXER_ADMIN_PASSWORD, aucun job
# de cette usine ne pousse aujourd'hui ce mot de passe vers l'API Wazuh
# (wazuh-apid) - en generer un nouveau au hasard ici casserait
# l'authentification au lieu de la reparer.
#
# CORRIGE LE 2026-09-09 (incident reel deploiement MIPREL2) : si le
# fichier est absent, on tente desormais UNE valeur connue et non
# inventee - le defaut d'installation Wazuh reel pour l'utilisateur API
# "wazuh" (verifie en reel ce jour : curl direct contre
# /security/user/authenticate a rendu un vrai jeton JWT) - jamais ecrit
# en aveugle : seule une authentification REELLEMENT reussie contre
# CETTE instance precise fait persister la valeur. Si ce defaut ne
# fonctionne pas (mot de passe deja change par l'operateur), on retombe
# sur l'erreur claire d'origine, jamais un mot de passe invente a la
# place de la vraie valeur inconnue.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

# CORRIGE LE 2026-09-09 (incident reel, VM neuve) : un seul essai,
# lance a peine 1 seconde apres la fin de WAZ_021_RECOVER (retablissement
# du reseau coupe par le crash-test WAZ_018_NET) - a tort rapporte "mot
# de passe incorrect", alors qu'un test manuel identique (memes
# identifiants "wazuh"/"wazuh") a rendu un vrai jeton JWT valide
# quelques minutes plus tard. Meme famille de bug deja rencontree et
# corrigee plusieurs fois ce jour (WAZ_014/WAZ_020_VERIFY/WAZ_037) : un
# composant qui vient de subir une perturbation (ici, la coupure/
# retablissement reseau) peut avoir besoin de quelques secondes de plus
# pour stabiliser sa propre API, meme si le service lui-meme repond
# "actif". Corrige par un reessai borne (6 tentatives, 5s d'ecart) -
# jamais un mot de passe different tente, uniquement une patience reelle
# avant de conclure a un echec.
_waz022_auth_reussie(){
  local pw="$1"
  local tentative
  for tentative in 1 2 3 4 5 6; do
    curl -s -u "${WAZ_API_USER}:${pw}" -k \
      "https://127.0.0.1:${WAZ_API_PORT}/security/user/authenticate" -X POST -o "${WORK_TMP_DIR}/waz022.json"
    if python3 -c "import json; d=json.load(open('${WORK_TMP_DIR}/waz022.json')); assert 'data' in d" 2>/dev/null; then
      return 0
    fi
    [ "$tentative" -lt 6 ] && sleep 5
  done
  return 1
}

if [ ! -f "$WAZ_API_PASSWORD_FILE" ]; then
  echo "[WAZ_022] ${WAZ_API_PASSWORD_FILE} absent - tentative du defaut d'installation Wazuh connu ('wazuh'), verifie par un vrai appel authentifie avant toute ecriture..."
  if _waz022_auth_reussie "wazuh"; then
    mkdir -p "$(dirname "$WAZ_API_PASSWORD_FILE")"
    printf '%s' "wazuh" > "$WAZ_API_PASSWORD_FILE"
    chmod 600 "$WAZ_API_PASSWORD_FILE"
    echo "[WAZ_022] Defaut confirme par authentification reelle - ecrit dans ${WAZ_API_PASSWORD_FILE}."
    echo "[WAZ_022] OK."
    rm -f "${WORK_TMP_DIR}/waz022.json"
    exit 0
  fi
  echo "[WAZ_022] Le defaut 'wazuh' ne fonctionne pas contre cette instance (mot de passe deja change ?)." >&2
fi

WAZ_API_PASSWORD="$(read_or_generate_secret "$WAZ_API_PASSWORD_FILE" non)" || exit 1

echo "[WAZ_022] Authentification aupres de l'API Wazuh..."
if _waz022_auth_reussie "$WAZ_API_PASSWORD"; then
  echo "[WAZ_022] OK."
  rm -f "${WORK_TMP_DIR}/waz022.json"
  exit 0
fi
echo "[WAZ_022] ERREUR, voir ${WORK_TMP_DIR}/waz022.json"; exit 1
