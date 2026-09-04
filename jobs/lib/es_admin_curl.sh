# es_admin_curl.sh - helper pour les appels ADMINISTRATIFS internes
# (creation de pipelines/templates/policies), distinct de es_auth.sh
# qui sert uniquement aux CONSOMMATEURS EXTERNES (Logstash, Beats...).
# Utilise le compte superutilisateur 'elastic' + son mot de passe
# bootstrap (arme par ES_022), jamais le token/mot de passe d'ingestion.
#
# CORRECTIF 2026-08-14 (incident reel pre-demo) : state/es_bootstrap_password.secret
# peut diverger du mot de passe REELLEMENT actif dans le cluster si le
# dossier de donnees Elasticsearch a survecu d'une tentative de
# deploiement anterieure sur la meme machine (bootstrap.password dans le
# keystore n'est lu qu'a la toute premiere creation de l'index de
# securite - inoperant sur un cluster deja initialise). Vu en reel :
# ES_022/ES_026/ES_027 passaient tous "OK" alors que le mot de passe
# stocke ne fonctionnait plus, decouvert seulement 2 jobs plus tard
# (ES_028) avec une erreur 401 sans lien evident avec sa vraie cause.
#
# Desormais, jamais suppose : avant tout appel admin, une verification
# legere (_cluster/health) confirme que le mot de passe stocke
# fonctionne reellement. S'il ne fonctionne pas, reinitialiser_mdp_elastic.sh
# est invoque automatiquement (SEUL point sanctionne pour toucher ce mot
# de passe - state/es_bootstrap_password.secret reste LA reference
# unique, jamais deux endroits differents a synchroniser a la main) puis
# l'appel est retente une fois. Echec bruyant, jamais silencieux, si
# l'authentification ne passe toujours pas apres reinitialisation.
es_admin_curl() {
  local pwfile="${STATE_DIR}/es_bootstrap_password.secret"
  [ -f "$pwfile" ] || { echo "[es_admin_curl] ERREUR : $pwfile absent (ES_022 doit avoir tourne)." >&2; return 1; }

  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --cacert "${PKI_DIR}/factory_ca.crt" -u "elastic:$(cat "$pwfile")" "https://127.0.0.1:${ES_PORT}/_cluster/health" 2>/dev/null)

  if [ "$http_code" = "401" ]; then
    echo "[es_admin_curl] ALERTE : mot de passe 'elastic' desynchronise (HTTP 401) - reinitialisation automatique via bin/reinitialiser_mdp_elastic.sh..." >&2
    if ! "${INSTALL_DIR}/bin/reinitialiser_mdp_elastic.sh" --silencieux; then
      echo "[es_admin_curl] ERREUR : echec de la reinitialisation automatique. Intervention manuelle requise (./bin/reinitialiser_mdp_elastic.sh)." >&2
      return 1
    fi
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --cacert "${PKI_DIR}/factory_ca.crt" -u "elastic:$(cat "$pwfile")" "https://127.0.0.1:${ES_PORT}/_cluster/health" 2>/dev/null)
    if [ "$http_code" = "401" ]; then
      echo "[es_admin_curl] ERREUR : authentification toujours en echec apres reinitialisation. Intervention manuelle requise." >&2
      return 1
    fi
    echo "[es_admin_curl] Mot de passe resynchronise avec succes, appel poursuivi normalement." >&2
  fi

  curl -s --cacert "${PKI_DIR}/factory_ca.crt" -u "elastic:$(cat "$pwfile")" "$@"
}
