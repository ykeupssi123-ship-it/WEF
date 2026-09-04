# test_data_tools.sh - outils de test pour la refonte de la bascule
# Kibana<->Wazuh (WAZ_035x/039x) : chargement de donnees factices en
# masse (pour avoir quelque chose de reel a couper/migrer lors d'un
# premier essai) et purge complete d'un pattern d'index.
#
# AJOUTE LE 2026-09-03 (demande explicite utilisateur, voir
# docs/JOURNAL_TECHNIQUE.md) : "charger... ces BD NoSQL (wazuh indexer
# et elasticsearch) de plein de donnees comme ca on aura de quoi faire
# les televersements" + "un job capable de vider" chaque cote apres
# coup. Jamais mélangé avec les vraies alertes de production - toujours
# un champ "wef_test_seed": true distinctif sur chaque document genere,
# pour pouvoir un jour filtrer/auditer sans ambiguite ce qui vient d'un
# essai plutot que d'une vraie detection.

# seed_test_alerts <url> <user> <pw> <ca_file> <index_name> <count>
# Insere <count> documents synthetiques (forme d'alerte Wazuh plausible)
# dans <index_name> via _bulk, par lots de 1000.
seed_test_alerts() {
  local url="$1" user="$2" pw="$3" ca_file="$4" index_name="$5" count="$6"
  URL="$url" USER="$user" PW="$pw" CA_FILE="$ca_file" INDEX_NAME="$index_name" COUNT="$count" \
  python3 << 'PYEOF'
import os, json, ssl, base64, random, urllib.request, datetime

url = os.environ['URL']; user = os.environ['USER']; pw = os.environ['PW']
ca_file = os.environ['CA_FILE']; index_name = os.environ['INDEX_NAME']
count = int(os.environ['COUNT'])

ctx = ssl.create_default_context(cafile=ca_file)
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

tok = base64.b64encode(f"{user}:{pw}".encode()).decode()
headers = {"Authorization": f"Basic {tok}", "Content-Type": "application/json"}

rules = [(5501, 3, "PAM: Login session opened"), (5710, 5, "sshd: Attempt to login using a non-existent user"),
         (100101, 3, "WEF canary"), (31151, 6, "Web attack: SQL injection")]
inserted = 0
batch_size = 1000
while inserted < count:
    this_batch = min(batch_size, count - inserted)
    lines = []
    for i in range(this_batch):
        rid, level, desc = random.choice(rules)
        now = datetime.datetime.utcnow().isoformat() + "Z"
        doc = {
            "timestamp": now,
            "rule": {"id": str(rid), "level": level, "description": desc},
            "agent": {"id": "000", "name": "localhost.localdomain"},
            "manager": {"name": "localhost.localdomain"},
            "location": "wef-seed-test",
            "full_log": f"WEF seed test event #{inserted + i}",
            "wef_test_seed": True,
        }
        lines.append(json.dumps({"index": {"_index": index_name}}))
        lines.append(json.dumps(doc))
    body = ("\n".join(lines) + "\n").encode()
    req = urllib.request.Request(f"{url}/_bulk", data=body, method='POST', headers=headers)
    with urllib.request.urlopen(req, context=ctx, timeout=120) as resp:
        result = json.loads(resp.read().decode())
    if result.get('errors'):
        for item in result.get('items', []):
            if 'error' in item.get('index', {}):
                raise SystemExit(f"ERREUR bulk (seed) : {item['index']['error']}")
    inserted += this_batch

req = urllib.request.Request(f"{url}/{index_name}/_refresh", method='POST', headers=headers)
urllib.request.urlopen(req, context=ctx, timeout=60)
print(f"INSERE={inserted}")
PYEOF
}

# purge_index_pattern <url> <user> <pw> <ca_file> <index_pattern>
# Supprime TOUS les documents du pattern donne (delete_by_query,
# match_all) et confirme un compte a 0 apres coup. N'existe QUE pour un
# usage volontaire (bin/order_job.sh) - jamais dans une chaine automatique.
purge_index_pattern() {
  local url="$1" user="$2" pw="$3" ca_file="$4" index_pattern="$5"
  URL="$url" USER="$user" PW="$pw" CA_FILE="$ca_file" INDEX_PATTERN="$index_pattern" \
  python3 << 'PYEOF'
import os, json, ssl, base64, urllib.request, urllib.error

url = os.environ['URL']; user = os.environ['USER']; pw = os.environ['PW']
ca_file = os.environ['CA_FILE']; index_pattern = os.environ['INDEX_PATTERN']

ctx = ssl.create_default_context(cafile=ca_file)
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

tok = base64.b64encode(f"{user}:{pw}".encode()).decode()
headers = {"Authorization": f"Basic {tok}", "Content-Type": "application/json"}

def call(path, method, body=None, timeout=180):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"{url}{path}", data=data, method=method, headers=headers)
    with urllib.request.urlopen(req, context=ctx, timeout=timeout) as resp:
        return json.loads(resp.read().decode())

def count(pattern):
    try:
        return call(f"/{pattern}/_count", 'GET').get('count', 0)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return 0
        raise

before = count(index_pattern)
print(f"AVANT_PURGE={before}")
if before == 0:
    print("APRES_PURGE=0")
    raise SystemExit(0)

call(f"/{index_pattern}/_delete_by_query?conflicts=proceed&wait_for_completion=true", 'POST', {"query": {"match_all": {}}})
call(f"/{index_pattern}/_refresh", 'POST')
after = count(index_pattern)
print(f"APRES_PURGE={after}")
if after != 0:
    raise SystemExit(f"ERREUR : {after} document(s) restant(s) apres purge.")
PYEOF
}
