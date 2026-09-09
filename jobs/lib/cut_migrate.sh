# cut_migrate.sh - helper de migration "coupee" (cut, pas copie) entre
# deux clusters compatibles OpenSearch/Elasticsearch (wazuh-indexer <->
# Elasticsearch), utilise par la bascule Kibana<->Wazuh (WAZ_035x/039x).
#
# AJOUTE LE 2026-09-03 (refonte demandee par l'utilisateur de la bascule
# de mode, voir docs/JOURNAL_TECHNIQUE.md). Extrait et generalise du code
# de migration scroll+bulk deja PROUVE fonctionnel en reel (present dans
# les anciennes versions monolithiques de WAZ_035_MODE_CONVERGENT.sh et
# WAZ_039_MODE_SOUVERAIN.sh, 2026-08-31) - jamais reecrit de zero, la
# logique scroll+bulk+refresh-avant-comptage reste identique, seule
# l'etape de suppression source est nouvelle.
#
# SEMANTIQUE "COUPER" (demande explicite utilisateur, 2026-09-03) :
# jamais de suppression AVANT confirmation stricte que TOUTE la donnee
# est bien arrivee a destination (compte destination >= compte source
# AVANT suppression). Si la copie echoue ou est incomplete, la source
# n'est JAMAIS touchee - etat "duplique" (moins grave qu'une perte de
# donnees) plutot que de parier sur une suppression optimiste.
#
# Usage : cut_migrate_alerts <src_url> <src_user> <src_pw> <dst_url> \
#           <dst_user> <dst_pw> <ca_file> <index_pattern>
# Retourne 0 et affiche SOURCE_AVANT=/MIGRE=/DESTINATION_APRES=/
# SOURCE_APRES_SUPPRESSION= sur stdout si la coupure complete a reussi
# (y compris le cas "rien a migrer" : compte source deja a 0). Retourne
# 1 et un message d'erreur explicite sur stderr sinon - jamais un echec
# silencieux.
cut_migrate_alerts() {
  local src_url="$1" src_user="$2" src_pw="$3"
  local dst_url="$4" dst_user="$5" dst_pw="$6"
  local ca_file="$7" index_pattern="$8"

  SRC_URL="$src_url" SRC_USER="$src_user" SRC_PW="$src_pw" \
  DST_URL="$dst_url" DST_USER="$dst_user" DST_PW="$dst_pw" \
  CA_FILE="$ca_file" INDEX_PATTERN="$index_pattern" \
  python3 << 'PYEOF'
import os, json, ssl, base64, time, urllib.request, urllib.error

src_url = os.environ['SRC_URL']; src_auth = (os.environ['SRC_USER'], os.environ['SRC_PW'])
dst_url = os.environ['DST_URL']; dst_auth = (os.environ['DST_USER'], os.environ['DST_PW'])
ca_file = os.environ['CA_FILE']
index_pattern = os.environ['INDEX_PATTERN']

ctx = ssl.create_default_context(cafile=ca_file)
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

def hdr(user, pw, ctype=True):
    tok = base64.b64encode(f"{user}:{pw}".encode()).decode()
    h = {"Authorization": f"Basic {tok}"}
    if ctype:
        h["Content-Type"] = "application/json"
    return h

def call(url, method, auth, body=None, timeout=60):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers=hdr(*auth))
    with urllib.request.urlopen(req, context=ctx, timeout=timeout) as resp:
        return json.loads(resp.read().decode())

def count(url, auth, pattern):
    try:
        r = call(f"{url}/{pattern}/_count", 'GET', auth)
        return r.get('count', 0)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return 0
        raise

# AJOUTE LE 2026-09-09 (incident reel deploiement MIPREL2, meme classe
# de contention deja rencontree plusieurs fois ce jour) : le premier lot
# _bulk vers un index de destination JAMAIS ECRIT AVANT declenche sa
# creation automatique - son shard primaire (1 seul, cluster mono-noeud)
# met parfois plus de temps a devenir actif que le lot suivant n'en
# laisse, sous la charge deja connue de cette VM (2 vCPU, 6 services).
# Erreur reelle observee : "unavailable_shards_exception ... primary
# shard is not active Timeout: [1m]". Jamais une erreur de donnee (le
# lot lui-meme est intact, rejouer le MEME lot avec les MEMES _id est
# sans risque - un bulk "index" ecrase, ne duplique jamais). Reessai
# borne (6 tentatives, 5s d'ecart) UNIQUEMENT si TOUTES les erreurs du
# lot sont bien ce type transitoire precis - toute autre erreur reelle
# (mapping incompatible, document malforme...) remonte immediatement,
# jamais masquee par une boucle de reessai aveugle.
def bulk_write(dst_url, dst_auth, bulk_body, max_retries=6, delay=5):
    result = None
    for attempt in range(1, max_retries + 1):
        req = urllib.request.Request(f"{dst_url}/_bulk", data=bulk_body, method='POST', headers=hdr(*dst_auth))
        with urllib.request.urlopen(req, context=ctx, timeout=120) as r2:
            result = json.loads(r2.read().decode())
        if not result.get('errors'):
            return result
        items_en_erreur = [item['index']['error'] for item in result.get('items', []) if 'error' in item.get('index', {})]
        toutes_transitoires = items_en_erreur and all(e.get('type') == 'unavailable_shards_exception' for e in items_en_erreur)
        if not toutes_transitoires:
            return result
        if attempt < max_retries:
            time.sleep(delay)
    return result

def migrate_all(src_url, src_auth, dst_url, dst_auth, index_pattern):
    """Scroll+bulk TOUT ce qui est actuellement cote source vers la
    destination. Retourne (nb_vu, dst_count_after_refresh)."""
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
        result = bulk_write(dst_url, dst_auth, bulk_body)
        if result.get('errors'):
            for item in result.get('items', []):
                if 'error' in item.get('index', {}):
                    raise SystemExit(f"ERREUR bulk (copie) : {item['index']['error']}")
        migrated += len(hits)
        resp = call(f"{src_url}/_search/scroll", 'POST', src_auth, {"scroll": "2m", "scroll_id": scroll_id})
        scroll_id = resp.get('_scroll_id')
        hits = resp['hits']['hits']
    # Rafraichissement explicite avant de compter - meme correctif reel
    # que le code d'origine (2026-08-31, decouvert au premier test en
    # direct) : sans lui, "_count" peut repondre avant que les documents
    # fraichement "_bulk" inseres ne deviennent visibles (near-real-time
    # normal d'OpenSearch/Elasticsearch, jamais une vraie perte).
    call(f"{dst_url}/{index_pattern}/_refresh", 'POST', dst_auth)
    return migrated, count(dst_url, dst_auth, index_pattern)

src_count_before = count(src_url, src_auth, index_pattern)
if src_count_before == 0:
    print("SOURCE_AVANT=0")
    print("MIGRE=0")
    print("SOURCE_APRES_SUPPRESSION=0")
    raise SystemExit(0)

migrated, dst_count_after = migrate_all(src_url, src_auth, dst_url, dst_auth, index_pattern)
print(f"SOURCE_AVANT={src_count_before}")
print(f"MIGRE={migrated}")
print(f"DESTINATION_APRES={dst_count_after}")
if dst_count_after < src_count_before:
    raise SystemExit(f"ERREUR : destination ({dst_count_after}) < source ({src_count_before}) apres copie - migration incomplete, SOURCE NON TOUCHEE (aucune suppression tentee).")

# --- Etape "coupe" (2026-09-03) : suppression source, jamais tentee
# avant la verification stricte ci-dessus. ---
#
# CORRIGE LE 2026-09-09 (incident reel, VM neuve : 12 documents restants
# apres un premier passage complet - "SOURCE_AVANT=174, MIGRE=174,
# DESTINATION_APRES=174, SOURCE_APRES_SUPPRESSION=12"). Cause reelle,
# jamais un bug de comptage : WAZ_035A_PAUSE_DEP_JOBS (job precedent
# dans la chaine) suspend les JOBS de l'orchestrateur qui dependent de
# wazuh-indexer, mais ne coupe JAMAIS le pipeline Logstash reellement
# actif (WAZ_014B_ALERTS_TO_INDEXER, service systemd toujours en marche)
# qui continue d'ecrire de VRAIES nouvelles alertes en direct pendant
# toute la duree de cette migration. "_delete_by_query" fait sa propre
# recherche interne au moment ou il demarre - les documents arrives
# APRES ce point de depart (mais avant sa fin) survivent, alors qu'ils
# n'ont pas non plus ete captes par le scroll de migration (deja
# termine plus tot). Donnee jamais perdue (toujours presente cote
# source, jamais supprimee avant verification), mais le job echouait a
# tort sur un flux d'ingestion normal et attendu.
# Corrige par un reessai borne : si des documents restent apres la
# suppression, ce sont par construction des arrivees recentes (jamais
# la meme donnee deux fois, un cluster mono-noeud ne perd rien) - on les
# migre et on les supprime a leur tour, jusqu'a convergence reelle vers
# 0 ou epuisement du budget de tentatives (le flux d'ingestion de ce
# projet est un flux de demo/test borne, pas un firehose infini - la
# convergence est attendue, jamais garantie a l'infini).
MAX_CUT_PASSES = 5
for cut_attempt in range(1, MAX_CUT_PASSES + 1):
    call(f"{src_url}/{index_pattern}/_delete_by_query?conflicts=proceed&wait_for_completion=true", 'POST', src_auth, {"query": {"match_all": {}}}, timeout=180)
    call(f"{src_url}/{index_pattern}/_refresh", 'POST', src_auth)
    src_count_after = count(src_url, src_auth, index_pattern)
    if src_count_after == 0:
        break
    if cut_attempt < MAX_CUT_PASSES:
        print(f"[cut_migrate] {src_count_after} document(s) arrive(s) pendant la coupure (ingestion en direct toujours active) - migration+suppression du reliquat (tentative {cut_attempt}/{MAX_CUT_PASSES})...")
        extra_migrated, _ = migrate_all(src_url, src_auth, dst_url, dst_auth, index_pattern)
        migrated += extra_migrated

print(f"SOURCE_APRES_SUPPRESSION={src_count_after}")
if src_count_after != 0:
    raise SystemExit(f"ERREUR : {src_count_after} document(s) restant(s) cote source apres {MAX_CUT_PASSES} tentatives de coupure - donnee dupliquee, PAS perdue : verifier manuellement avant de rejouer (flux d'ingestion anormalement rapide ?).")
PYEOF
}
