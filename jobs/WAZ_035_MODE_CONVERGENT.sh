#!/bin/bash
# SUPERSEDE LE 2026-09-03 - plus reference dans jobs_table.csv. Remplace
# par la cascade granulaire WAZ_035_KIBANA_TRIGGER/035A/035B/035C/035D
# (voir docs/JOURNAL_TECHNIQUE.md pour le diagnostic complet). Conserve
# ici seulement comme trace historique - ne pas rejouer directement.
# WAZ_035_MODE_CONVERGENT - WEF_WAZ_RUN_SWTOKIB
# Vanne un-clic REVERSIBLE : bascule EXCLUSIVE des alertes Wazuh vers
# Elasticsearch/Kibana (et extinction du Dashboard natif Wazuh, devenu
# sans nouvelle donnee a montrer).
#
# REECRIT EN ENTIER LE 2026-08-31 (demande explicite utilisateur, "bascule
# à la demande" entre les deux tableaux de bord). Cette version REMPLACE
# completement l'ancien mecanisme de ce meme job (conserve seulement
# comme trace dans l'historique git/archive) - diagnostic complet de
# pourquoi l'ancien mecanisme est abandonne, jamais suppose inutile sans
# preuve :
#
#   ANCIEN MECANISME (2026-08-12 -> 2026-08-30) : routait un flux
#   <syslog_output> brut (port 5000, JSON) du manager vers Logstash, et
#   coupait ENTIEREMENT wazuh-indexer + wazuh-dashboard ("systemctl stop
#   wazuh-indexer wazuh-dashboard"). Deux defauts reels, decouverts en
#   construisant le pipeline d'alertes definitif (WAZ_014B, 2026-08-30) :
#     (1) wazuh-indexer est desormais utilise en continu par bien plus
#         que le seul Dashboard - inventaire/vulnerabilites natifs
#         (WAZ_014E), politiques ISM de retention (WAZ_014D), verrous
#         flood-stage (WAZ_042), rafraichissement de cache de champs
#         (WAZ_043), et surtout INFRA_004_HEALTH_GUARDIAN.sh qui alerte
#         desormais si wazuh-indexer.service n'est pas actif en
#         permanence. L'arreter a chaque bascule casserait tout cela.
#     (2) le flux <syslog_output> brut n'a jamais ete le meme pipeline
#         que les VRAIES alertes structurees et correctement mappees
#         (voir WAZ_014B/WAZ_014C, le correctif du champ "host" objet) -
#         Kibana aurait montre un flux pauvre et distinct, jamais "tout
#         ce qu'on voit sur le Dashboard Wazuh".
#
#   NOUVEAU MECANISME (celui-ci) : le pipeline Logstash dedie deja en
#   place pour les alertes (WAZ_014B, fichier /etc/logstash/wazuh-
#   alerts.conf, lit /var/ossec/logs/alerts/alerts.json en continu) reste
#   la SEULE source - ce job ne change QUE sa DESTINATION de sortie
#   (wazuh-indexer <-> Elasticsearch classique), jamais sa source.
#   wazuh-indexer.service n'est JAMAIS arrete par ce job - seul
#   wazuh-dashboard.service (l'interface web) est eteint, puisqu'il
#   n'aurait plus rien de frais a montrer une fois la destination
#   basculee. Semantique EXACTE demandee par l'utilisateur (2026-08-31,
#   verbatim reformule) : "que lorsqu'on choisit de se deplacer de
#   Wazuh Dashboard vers Kibana, les donnees (dont les alertes) se
#   deplacent aussi vers Elasticsearch, et il n'y a plus rien qui est
#   ecrit dans l'indexeur Wazuh" - c'est exactement ce que fait ce job :
#     1. Migration REELLE de l'historique deja present dans wazuh-indexer
#        (index wazuh-alerts-4.x-*) vers Elasticsearch, via scroll+bulk
#        (memes _id conserves - idempotent, un rejeu de la migration
#        n'ecrase jamais un doublon, il ecrase le meme document).
#     2. Reecriture du pipeline WAZ_014B pour que TOUTE alerte FUTURE
#        parte vers Elasticsearch au lieu de wazuh-indexer - plus rien
#        n'est ecrit dans wazuh-indexer a partir de ce point.
#     3. Extinction de wazuh-dashboard (rien de neuf a y montrer).
#   Reversible integralement par WAZ_039_MODE_SOUVERAIN.sh (miroir exact,
#   sens inverse).
#
# ETAT DE BASCULE : trace dans ${STATE_DIR}/WAZ_ALERTS_ROUTE.state
# ("INDEXER" ou "ELASTICSEARCH") - jamais devine depuis l'etat des
# services (un wazuh-dashboard arrete manuellement par un operateur ne
# doit pas etre pris pour une bascule reelle). Idempotent : rejouer ce
# job alors qu'on est deja en mode Kibana ne fait rien (ni migration ni
# redemarrage inutiles).
#
# CHAINE (jobs_table.csv, inchangee) : ce job reste enchaine avec
# WAZ_036_KIBANA_INDEX (cree le data view Kibana, toujours valable tel
# quel) -> WAZ_037_CONVERGENT_TEST (reecrit ce meme jour, verification
# reelle) -> WAZ_038_KIBANA_VERIFY (sante Kibana, inchange) ->
# WAZ_039_MODE_SOUVERAIN (reecrit ce meme jour, retour a l'etat par
# defaut) -> WAZ_040_KIBANA_SILENT (reecrit ce meme jour) - ce passage
# automatique lors d'un premier deploiement a froid sert d'auto-test des
# DEUX sens de la bascule avant de revenir a l'etat par defaut
# (Souverain/Wazuh Dashboard). Pour re-basculer manuellement plus tard en
# exploitation, rejouer ce script seul via forcer_job.sh WAZ_035_MODE_CONVERGENT.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
source "$PROJECT_ROOT/jobs/lib/es_admin_curl.sh"

ROUTE_STATE_FILE="${STATE_DIR}/WAZ_ALERTS_ROUTE.state"
CURRENT_ROUTE="$(cat "$ROUTE_STATE_FILE" 2>/dev/null || echo INDEXER)"
if [ "$CURRENT_ROUTE" = "ELASTICSEARCH" ]; then
  echo "[WAZ_035_MODE_CONVERGENT] Deja en mode convergent (route=ELASTICSEARCH dans ${ROUTE_STATE_FILE}), rien a faire."
  exit 0
fi

WAZUH_INDEXER_ADMIN_PW="$(read_or_generate_secret "$WAZ_INDEXER_ADMIN_PASSWORD_FILE" non)" || exit 1
WAZ_INDEXER_PORT="${WAZ_INDEXER_PORT:-9200}"
ES_BOOTSTRAP_PW_FILE="${STATE_DIR}/es_bootstrap_password.secret"
[ -f "$ES_BOOTSTRAP_PW_FILE" ] || { echo "[WAZ_035_MODE_CONVERGENT] ERREUR : ${ES_BOOTSTRAP_PW_FILE} absent (ES_022 doit avoir tourne)." >&2; exit 1; }
ES_BOOTSTRAP_PW="$(cat "$ES_BOOTSTRAP_PW_FILE")"

echo "[WAZ_035_MODE_CONVERGENT] Verification reelle qu'Elasticsearch (ELK classique) est joignable et authentifie..."
HTTP_CODE=$(es_admin_curl -o /dev/null -w '%{http_code}' "https://127.0.0.1:${ES_PORT}/_cluster/health" 2>/dev/null)
if [ "$HTTP_CODE" != "200" ]; then
  echo "[WAZ_035_MODE_CONVERGENT] ERREUR : Elasticsearch injoignable ou authentification en echec (HTTP ${HTTP_CODE})." >&2
  exit 1
fi

echo "[WAZ_035_MODE_CONVERGENT] Migration de l'historique des alertes (wazuh-indexer -> Elasticsearch)..."
MIGRATION_LOG="$(mktemp)"
SRC_URL="https://127.0.0.1:${WAZ_INDEXER_PORT}" SRC_USER="${WAZ_INDEXER_ADMIN_USER}" SRC_PW="$WAZUH_INDEXER_ADMIN_PW" \
DST_URL="https://127.0.0.1:${ES_PORT}" DST_USER="elastic" DST_PW="$ES_BOOTSTRAP_PW" \
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

    # Rafraichissement EXPLICITE avant de compter - decouvert en reel
    # (premier test en direct, 2026-08-31) : sans lui, "_count" peut
    # repondre AVANT que les documents fraichement "_bulk" inseres ne
    # deviennent visibles a la recherche (comportement near-real-time
    # normal d'OpenSearch/Elasticsearch, jamais une vraie perte de
    # documents - reconfirme a la main juste apres coup : le compte
    # remontait bien au total exact quelques secondes plus tard). Un
    # refresh explicite rend la verification fiable immediatement,
    # plutot que d'ajouter un delai arbitraire (sleep) qui resterait un
    # pari sur la vitesse du cluster a un instant donne.
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
  echo "[WAZ_035_MODE_CONVERGENT] ERREUR : la migration de l'historique a echoue (voir sortie Python ci-dessus)." >&2
  rm -f "$MIGRATION_LOG"
  exit 1
fi
rm -f "$MIGRATION_LOG"

echo "[WAZ_035_MODE_CONVERGENT] Reecriture du pipeline Logstash dedie (destination -> Elasticsearch classique)..."
LS_CERTS="/etc/logstash/certs"
PIPELINE_CONF="/etc/logstash/wazuh-alerts.conf"
local_pki_copy "$LS_CERTS" "${LS_USER}:${LS_USER}"

if [ "${ES_AUTH_MODE:-token}" = "password" ]; then
  ES_OUT_AUTH_LINES="    user => \"factory_ingest_user\"
    password => \"\${factory_ingest_password}\""
else
  ES_OUT_AUTH_LINES="    api_key => \"\${factory_ingest_token}\""
fi

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
  elasticsearch {
    hosts => ["https://127.0.0.1:${ES_PORT}"]
${ES_OUT_AUTH_LINES}
    ssl_certificate_authorities => ["${LS_CERTS}/factory_ca.crt"]
    index => "wazuh-alerts-4.x-%{+YYYY.MM.dd}"
  }
}
CONFEOF
chown "${LS_USER}:${LS_USER}" "$PIPELINE_CONF"
chmod 640 "$PIPELINE_CONF"

echo "[WAZ_035_MODE_CONVERGENT] Redemarrage de logstash (prise en compte de la nouvelle destination)..."
systemctl restart logstash 2>/dev/null || true
if ! wait_for_service_active logstash 120 5; then
  echo "[WAZ_035_MODE_CONVERGENT] ERREUR : logstash.service n'a pas redemarre. Diagnostic :" >&2
  journalctl -u logstash -n 30 --no-pager 2>/dev/null || true
  exit 1
fi

echo "[WAZ_035_MODE_CONVERGENT] Extinction du Dashboard natif Wazuh (wazuh-indexer reste actif, utilise par d'autres jobs d'exploitation)..."
systemctl stop wazuh-dashboard 2>/dev/null || true
systemctl disable wazuh-dashboard 2>/dev/null || true

echo "ELASTICSEARCH" > "$ROUTE_STATE_FILE"
echo "[WAZ_035_MODE_CONVERGENT] Bascule confirmee : alertes Wazuh -> Elasticsearch/Kibana, Wazuh Dashboard eteint, wazuh-indexer toujours actif."
echo "[WAZ_035_MODE_CONVERGENT] OK."
exit 0
