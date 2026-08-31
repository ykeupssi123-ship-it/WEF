# =====================================================================
# es_auth.sh - fonction partagee, sourcee par tout job ES qui doit
# appeler l'API. Deux modes, chacun arme par son propre job dedie,
# jamais l'un ne bloquant l'autre :
#   - TOKEN    : arme par ES_050 (API Key), state/factory_ingest_apikey.secret
#   - PASSWORD : arme par ES_050B (utilisateur nomme + mot de passe),
#                state/factory_ingest_password.secret
# Choix au moment de l'appel via ES_AUTH_MODE (vars.conf), pas fige en dur.
# =====================================================================

es_curl() {
  local mode="${ES_AUTH_MODE:-token}"
  local auth_args=()

  case "$mode" in
    token)
      local keyfile="${STATE_DIR}/factory_ingest_apikey.secret"
      [ -f "$keyfile" ] || { echo "[es_auth] ERREUR : $keyfile absent. Lancez ES_050 (mode token) d'abord, ou changez ES_AUTH_MODE=password." >&2; return 1; }
      auth_args=(-H "Authorization: ApiKey $(cat "$keyfile")")
      ;;
    password)
      local pwfile="${STATE_DIR}/factory_ingest_password.secret"
      [ -f "$pwfile" ] || { echo "[es_auth] ERREUR : $pwfile absent. Lancez ES_050B (mode password) d'abord, ou changez ES_AUTH_MODE=token." >&2; return 1; }
      auth_args=(-u "factory_ingest_user:$(cat "$pwfile")")
      ;;
    *)
      echo "[es_auth] ERREUR : ES_AUTH_MODE='$mode' invalide (token|password attendu)." >&2
      return 1
      ;;
  esac

  curl -s --cacert "${PKI_DIR}/factory_ca.crt" "${auth_args[@]}" "$@"
}
