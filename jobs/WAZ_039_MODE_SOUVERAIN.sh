#!/bin/bash
# SUPERSEDE LE 2026-09-03 - plus reference dans jobs_table.csv. Remplace
# par la cascade granulaire WAZ_039_WAZUH_TRIGGER/039A/039B/039C/039D
# (voir docs/JOURNAL_TECHNIQUE.md pour le diagnostic complet). Conserve
# ici seulement comme trace historique - ne pas rejouer directement.
# WAZ_039_MODE_SOUVERAIN - WEF_WAZ_RUN_SWTOSOV
# Vanne un-clic inverse de WAZ_035_MODE_CONVERGENT : bascule EXCLUSIVE
# des alertes Wazuh de retour vers wazuh-indexer (et reallumage du
# Dashboard natif Wazuh), coupe l'ecriture vers Elasticsearch/Kibana.
#
# REECRIT EN ENTIER LE 2026-08-31, miroir exact de WAZ_035_MODE_CONVERGENT
# - voir son en-tete pour le diagnostic complet du remplacement de
# l'ancien mecanisme <syslog_output>/arret-total-indexer. Semantique
# EXACTE demandee par l'utilisateur (2026-08-31, verbatim reformule) :
# "quand on fait l'inverse (Kibana -> Wazuh Dashboard), seules les
# alertes Wazuh vont vers l'indexeur au moment de la bascule, et elles
# ne s'ecrivent plus dans Elasticsearch mais plutot dans l'indexeur
# Wazuh" - c'est exactement ce que fait ce job :
#   1. Migration REELLE de l'historique accumule dans Elasticsearch
#      pendant le mode convergent (index wazuh-alerts-4.x-*) vers
#      wazuh-indexer, via scroll+bulk (memes _id conserves - idempotent).
#   2. Reecriture du pipeline WAZ_014B pour que TOUTE alerte FUTURE
#      reparte vers wazuh-indexer (destination d'origine) - plus rien
#      n'est ecrit dans Elasticsearch a partir de ce point.
#   3. Reallumage de wazuh-dashboard.
# wazuh-indexer n'a jamais ete arrete par le mode convergent - rien a
# redemarrer ici de ce cote, juste confirmer qu'il tourne toujours.
#
# ETAT DE BASCULE : ${STATE_DIR}/WAZ_ALERTS_ROUTE.state, miroir exact de
# WAZ_035. Idempotent : rejouer ce job alors qu'on est deja en mode
# souverain (ou fraichement deploye, jamais bascule) ne fait rien.
#
# CHAINE (jobs_table.csv, inchangee) : voir l'en-tete de
# WAZ_035_MODE_CONVERGENT.sh pour le detail de la chaine complete
# WAZ_035->040 (auto-test des deux sens a chaque deploiement a froid,
# etat final toujours Souverain par defaut). Pour re-basculer
# manuellement en exploitation, rejouer ce script seul via
# forcer_job.sh WAZ_039_MODE_SOUVERAIN.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
source "$PROJECT_ROOT/jobs/lib/es_admin_curl.sh"

ROUTE_STATE_FILE="${STATE_DIR}/WAZ_ALERTS_ROUTE.state"
CURRENT_ROUTE="$(cat "$ROUTE_STATE_FILE" 2>/dev/null || echo INDEXER)"
if [ "$CURRENT_ROUTE" != "ELASTICSEARCH" ]; then
  echo "[WAZ_039_MODE_SOUVERAIN] Deja en mode souverain (route=${CURRENT_ROUTE} dans ${ROUTE_STATE_FILE}), rien a faire."
  echo "[WAZ_039_MODE_SOUVERAIN] Confirmation que wazuh-dashboard est bien actif malgre tout..."
  systemctl enable wazuh-dashboard 2>/dev/null || true
  systemctl start wazuh-dashboard 2>/dev/null || true
  wait_for_service_active wazuh-dashboard 120 5 || { echo "[WAZ_039_MODE_SOUVERAIN] ERREUR : wazuh-dashboard n'a pas pu etre confirme actif." >&2; exit 1; }
  echo "[WAZ_039_MODE_SOUVERAIN] OK."
  exit 0
fi

WAZUH_INDEXER_ADMIN_PW="$(read_or_generate_secret "$WAZ_INDEXER_ADMIN_PASSWORD_FILE" non)" || exit 1
WAZ_INDEXER_PORT="${WAZ_INDEXER_PORT:-9200}"
ES_BOOTSTRAP_PW_FILE="${STATE_DIR}/es_bootstrap_password.secret"
[ -f "$ES_BOOTSTRAP_PW_FILE" ] || { echo "[WAZ_039_MODE_SOUVERAIN] ERREUR : ${ES_BOOTSTRAP_PW_FILE} absent (ES_022 doit avoir tourne)." >&2; exit 1; }
ES_BOOTSTRAP_PW="$(cat "$ES_BOOTSTRAP_PW_FILE")"

echo "[WAZ_039_MODE_SOUVERAIN] Verification reelle que wazuh-indexer est joignable..."
HTTP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' --cacert "${PKI_DIR}/factory_ca.crt" -u "${WAZ_INDEXER_ADMIN_USER}:${WAZUH_INDEXER_ADMIN_PW}" "https://127.0.0.1:${WAZ_INDEXER_PORT}/_cluster/health" 2>/dev/null)
if [ "$HTTP_CODE" != "200" ]; then
  echo "[WAZ_039_MODE_SOUVERAIN] ERREUR : wazuh-indexer injoignable ou authentification en echec (HTTP ${HTTP_CODE})." >&2
  exit 1
fi

echo "[WAZ_039_MODE_SOUVERAIN] Migration de l'historique accumule (Elasticsearch -> wazuh-indexer)..."
MIGRATION_LOG="$(mktemp)"
SRC_URL="https://127.0.0.1:${ES_PORT}" SRC_USER="elastic" SRC_PW="$ES_BOOTSTRAP_PW" \
DST_URL="https://127.0.0.1:${WAZ_INDEXER_PORT}" DST_USER="${WAZ_INDEXER_ADMIN_USER}" DST_PW="$WAZUH_INDEXER_ADMIN_PW" \
CA_FILE="${PKI_DIR}/factory_ca.crt" INDEX_PATTERN="wazuh-alerts-4.x-*" \
python3 > "$MIGRATION_LOG" << 'PYEOF'
import os, json, ssl, base64, urllib.request, urllib.error

src_url = os.environ['SRC_URL']; src_auth = (os.environ['SRC_USER'], os.environ['SRC_PW'])
dst_url = os.environ['DST_URL']; dst_auth = (os.environ['DST_USER'], os.environ['DST_PW'])
ca_file = os.environ['CA_FILE']
index_pattern = os.environ['INDEX_PATTERN']

ctx = ssl.create_default_context(cafile=ca_file)
# Meme choix que les nombreux "curl -sk" deja utilises partout ailleurs
# dans ce projet pour les appels admin ad-hoc en localhost (WAZ_042/043,
# etc.) : verification de nom d'hote/chaine desactivee plutot que
# parier que le certificat d'usine satisfasse la verification stricte
# par defaut de Python face a 127.0.0.1 sans l'avoir teste en reel.
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

def hdr(user, pw, ctype=True):
    tok = base64.b64encode(f"{user}:{pw}".encode()).decode()
    h = {"Authorization": f"Basic {tok}"}
    if ctype:
        h["Content-Type"] = "application/json"
    return h

def call(url, method, auth, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers=hdr(*auth))
    with urllib.request.urlopen(req, context=ctx, timeout=60) as resp:
        return json.loads(resp.read().decode())

def count(url, auth, pattern):
    try:
        r = call(f"{url}/{pattern}/_count", 'GET', auth)
        return r.get('count', 0)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return 0
        raise

src_count_before = count(src_url, src_auth, index_pattern)
if src_count_before == 0:
    print(f"AUCUN_DOCUMENT_SOURCE=0")
    print(f"MIGRE=0")
else:
    migrated = 0
    resp = call(f"{src_url}/{index_pattern}/_search?scroll=2m", 'POST', src_auth, {"size": 500, "query": {"match_all": {}}})
    scroll_id = resp.get('_scroll_id')
    hits = resp['hits']['hits']
    while hits:
        lines = []
        for h in hits:
            lines.append(json.dumps({"index": {"_index": h['_index'], "_id": h['_id']}}))
            lines.append(json.dumps(h['_source']))
        bulk_body = ("\n".join(lines) + "\n").encode()
        req = urllib.request.Request(f"{dst_url}/_bulk", data=bulk_body, method='POST', headers=hdr(*dst_auth))
        with urllib.request.urlopen(req, context=ctx, timeout=120) as r2:
            result = json.loads(r2.read().decode())
        if result.get('errors'):
            for item in result.get('items', []):
                if 'error' in item.get('index', {}):
                    raise SystemExit(f"ERREUR bulk : {item['index']['error']}")
        migrated += len(hits)
        resp = call(f"{src_url}/_search/scroll", 'POST', src_auth, {"scroll": "2m", "scroll_id": scroll_id})
        scroll_id = resp.get('_scroll_id')
        hits = resp['hits']['hits']

    # Rafraichissement EXPLICITE avant de compter - meme correctif reel
    # que WAZ_035_MODE_CONVERGENT.sh (voir son en-tete pour le diagnostic
    # complet, decouvert au premier test en direct de la bascule le
    # 2026-08-31) : sans lui, "_count" peut repondre avant que les
    # documents fraichement "_bulk" inseres ne deviennent visibles a la
    # recherche (near-real-time normal d'OpenSearch/Elasticsearch,
    # jamais une vraie perte).
    call(f"{dst_url}/{index_pattern}/_refresh", 'POST', dst_auth)
    dst_count_after = count(dst_url, dst_auth, index_pattern)
    print(f"SOURCE_AVANT={src_count_before}")
    print(f"MIGRE={migrated}")
    print(f"DESTINATION_APRES={dst_count_after}")
    if dst_count_after < src_count_before:
        raise SystemExit(f"ERREUR : destination ({dst_count_after}) < source ({src_count_before}) apres migration - migration incomplete.")
PYEOF
PY_EXIT=$?
cat "$MIGRATION_LOG"
if [ $PY_EXIT -ne 0 ]; then
  echo "[WAZ_039_MODE_SOUVERAIN] ERREUR : la migration de l'historique a echoue (voir sortie Python ci-dessus)." >&2
  rm -f "$MIGRATION_LOG"
  exit 1
fi
rm -f "$MIGRATION_LOG"

echo "[WAZ_039_MODE_SOUVERAIN] Reecriture du pipeline Logstash dedie (destination -> wazuh-indexer, etat d'origine)..."
LS_CERTS="/etc/logstash/certs"
PIPELINE_CONF="/etc/logstash/wazuh-alerts.conf"
local_pki_copy "$LS_CERTS" "${LS_USER}:${LS_USER}"

cat > "$PIPELINE_CONF" << CONFEOF
input {
  file {
    path => "/var/ossec/logs/alerts/alerts.json"
    start_position => "beginning"
    sincedb_path => "/var/lib/logstash/sincedb_wazuh_alerts"
    codec => "json"
  }
}
output {
  http {
    url => "https://127.0.0.1:${WAZ_INDEXER_PORT}/wazuh-alerts-4.x-%{+YYYY.MM.dd}/_doc"
    http_method => "post"
    format => "json"
    user => "${WAZ_INDEXER_ADMIN_USER}"
    password => "\${wazuh_indexer_admin_password}"
    cacert => "${LS_CERTS}/factory_ca.crt"
    retry_non_idempotent => true
  }
}
CONFEOF
chown "${LS_USER}:${LS_USER}" "$PIPELINE_CONF"
chmod 640 "$PIPELINE_CONF"

echo "[WAZ_039_MODE_SOUVERAIN] Redemarrage de logstash (prise en compte de la destination d'origine)..."
systemctl restart logstash 2>/dev/null || true
if ! wait_for_service_active logstash 120 5; then
  echo "[WAZ_039_MODE_SOUVERAIN] ERREUR : logstash.service n'a pas redemarre. Diagnostic :" >&2
  journalctl -u logstash -n 30 --no-pager 2>/dev/null || true
  exit 1
fi

echo "[WAZ_039_MODE_SOUVERAIN] Reallumage du Dashboard natif Wazuh..."
systemctl enable wazuh-dashboard 2>/dev/null || true
systemctl restart wazuh-dashboard 2>/dev/null || true
if ! wait_for_service_active wazuh-dashboard 120 5; then
  echo "[WAZ_039_MODE_SOUVERAIN] ERREUR : wazuh-dashboard n'a pas pu etre confirme actif." >&2
  exit 1
fi

echo "INDEXER" > "$ROUTE_STATE_FILE"
echo "[WAZ_039_MODE_SOUVERAIN] Bascule confirmee : alertes Wazuh -> wazuh-indexer, Wazuh Dashboard actif, Elasticsearch/Kibana n'ecrit plus rien de nouveau."
echo "[WAZ_039_MODE_SOUVERAIN] OK."
exit 0
