#!/bin/bash
# KB_031_MONITORING_DASHBOARDS - WEF_KB_RUN_MONDASH
#
# Cree deux vrais tableaux de bord Kibana (graphiques, pas une liste
# d'evenements ligne par ligne) - demande explicite : "un monitoring
# systeme des ressources comme dans une vue dashboard de EyesOfNetwork
# avec des diagrammes" (Metricbeat) et "une vue diagramme du comptage
# des elements" (Filebeat).
#
# Utilise l'API classique "saved_objects" de Kibana (type
# "visualization"/"dashboard", agregations visState) - format stable et
# documente depuis des annees, contrairement au format interne de Lens
# (non documente, change selon la version) : c'est le meme choix de
# prudence que le reste de l'usine (jamais parier sur un format non
# garanti). S'appuie sur le data view "log-dataview" deja cree par
# KB_030_GENERIC_LOG_DATAVIEW (doit avoir tourne avant celui-ci).
#
# Idempotent : chaque objet a un id fixe, poste avec ?overwrite=true -
# rejouable sans erreur (meme discipline que BEAC_004/WAZ_036).
set -uo pipefail
source "$VARS_FILE"

BOOTSTRAP_PW_FILE="${STATE_DIR}/es_bootstrap_password.secret"
[ -f "$BOOTSTRAP_PW_FILE" ] || { echo "[KB_031_MONITORING_DASHBOARDS] ERREUR : $BOOTSTRAP_PW_FILE absent (ES_022 doit avoir tourne sur ELK_HOST)."; exit 1; }
BOOTSTRAP_PW="$(cat "$BOOTSTRAP_PW_FILE")"

DATAVIEW_ID="log-dataview"
KB_BASE="https://127.0.0.1:${KB_PORT}/api/saved_objects"
WORKDIR="$(mktemp -d)"
FAILED=0

post_object() {
  local type="$1" id="$2" file="$3" label="$4"
  local resp
  resp="$(mktemp)"
  local code
  code=$(curl -sk -u "elastic:${BOOTSTRAP_PW}" \
    -X POST "${KB_BASE}/${type}/${id}?overwrite=true" \
    -H "kbn-xsrf: true" -H "Content-Type: application/json" \
    -d "@${file}" -o "$resp" -w "%{http_code}")
  if [ "$code" != "200" ]; then
    echo "[KB_031_MONITORING_DASHBOARDS] ERREUR '${label}' (HTTP ${code}) :" >&2
    cat "$resp" >&2
    FAILED=1
  else
    echo "[KB_031_MONITORING_DASHBOARDS] OK : ${label}"
  fi
  rm -f "$resp"
}

# --- Reference commune vers le data view "log-*" ---
INDEX_REF='[{"name":"kibanaSavedObjectMeta.searchSourceJSON.index","type":"index-pattern","id":"'"${DATAVIEW_ID}"'"}]'

# ===================================================================
# METRICBEAT - 3 courbes dans le temps (CPU / memoire / reseau)
# ===================================================================

cat > "${WORKDIR}/viz-cpu.json" << 'JSONEOF'
{
  "attributes": {
    "title": "CPU par machine",
    "visState": "{\"title\":\"CPU par machine\",\"type\":\"line\",\"params\":{\"grid\":{\"categoryLines\":false},\"categoryAxes\":[{\"id\":\"CategoryAxis-1\",\"type\":\"category\",\"position\":\"bottom\",\"show\":true,\"title\":{\"text\":\"@timestamp\"}}],\"valueAxes\":[{\"id\":\"ValueAxis-1\",\"name\":\"LeftAxis-1\",\"type\":\"value\",\"position\":\"left\",\"show\":true,\"title\":{\"text\":\"Utilisation CPU (0-1)\"}}],\"seriesParams\":[{\"data\":{\"id\":\"1\",\"label\":\"Utilisation CPU\"},\"type\":\"line\",\"mode\":\"normal\",\"valueAxis\":\"ValueAxis-1\"}],\"legendPosition\":\"right\"},\"aggs\":[{\"id\":\"1\",\"enabled\":true,\"type\":\"avg\",\"schema\":\"metric\",\"params\":{\"field\":\"host.cpu.usage\"}},{\"id\":\"2\",\"enabled\":true,\"type\":\"date_histogram\",\"schema\":\"segment\",\"params\":{\"field\":\"@timestamp\",\"interval\":\"auto\"}},{\"id\":\"3\",\"enabled\":true,\"type\":\"terms\",\"schema\":\"group\",\"params\":{\"field\":\"host.hostname\",\"size\":5,\"order\":\"desc\",\"orderBy\":\"1\"}}]}",
    "uiStateJSON": "{}",
    "description": "Charge CPU normalisee, une courbe par machine.",
    "kibanaSavedObjectMeta": {
      "searchSourceJSON": "{\"query\":{\"query\":\"agent.type: metricbeat\",\"language\":\"kuery\"},\"filter\":[],\"indexRefName\":\"kibanaSavedObjectMeta.searchSourceJSON.index\"}"
    }
  }
}
JSONEOF

cat > "${WORKDIR}/viz-memory.json" << 'JSONEOF'
{
  "attributes": {
    "title": "Memoire utilisee (%) par machine",
    "visState": "{\"title\":\"Memoire utilisee (%) par machine\",\"type\":\"line\",\"params\":{\"grid\":{\"categoryLines\":false},\"categoryAxes\":[{\"id\":\"CategoryAxis-1\",\"type\":\"category\",\"position\":\"bottom\",\"show\":true,\"title\":{\"text\":\"@timestamp\"}}],\"valueAxes\":[{\"id\":\"ValueAxis-1\",\"name\":\"LeftAxis-1\",\"type\":\"value\",\"position\":\"left\",\"show\":true,\"title\":{\"text\":\"Memoire utilisee (0-1)\"}}],\"seriesParams\":[{\"data\":{\"id\":\"1\",\"label\":\"Memoire utilisee\"},\"type\":\"line\",\"mode\":\"normal\",\"valueAxis\":\"ValueAxis-1\"}],\"legendPosition\":\"right\"},\"aggs\":[{\"id\":\"1\",\"enabled\":true,\"type\":\"avg\",\"schema\":\"metric\",\"params\":{\"field\":\"system.memory.actual.used.pct\"}},{\"id\":\"2\",\"enabled\":true,\"type\":\"date_histogram\",\"schema\":\"segment\",\"params\":{\"field\":\"@timestamp\",\"interval\":\"auto\"}},{\"id\":\"3\",\"enabled\":true,\"type\":\"terms\",\"schema\":\"group\",\"params\":{\"field\":\"host.hostname\",\"size\":5,\"order\":\"desc\",\"orderBy\":\"1\"}}]}",
    "uiStateJSON": "{}",
    "description": "Pourcentage de RAM reellement utilisee, une courbe par machine.",
    "kibanaSavedObjectMeta": {
      "searchSourceJSON": "{\"query\":{\"query\":\"agent.type: metricbeat and metricset.name: memory\",\"language\":\"kuery\"},\"filter\":[],\"indexRefName\":\"kibanaSavedObjectMeta.searchSourceJSON.index\"}"
    }
  }
}
JSONEOF

cat > "${WORKDIR}/viz-network.json" << 'JSONEOF'
{
  "attributes": {
    "title": "Reseau (octets) par interface",
    "visState": "{\"title\":\"Reseau (octets) par interface\",\"type\":\"line\",\"params\":{\"grid\":{\"categoryLines\":false},\"categoryAxes\":[{\"id\":\"CategoryAxis-1\",\"type\":\"category\",\"position\":\"bottom\",\"show\":true,\"title\":{\"text\":\"@timestamp\"}}],\"valueAxes\":[{\"id\":\"ValueAxis-1\",\"name\":\"LeftAxis-1\",\"type\":\"value\",\"position\":\"left\",\"show\":true,\"title\":{\"text\":\"Octets\"}}],\"seriesParams\":[{\"data\":{\"id\":\"1\",\"label\":\"Entrant\"},\"type\":\"line\",\"mode\":\"normal\",\"valueAxis\":\"ValueAxis-1\"},{\"data\":{\"id\":\"2\",\"label\":\"Sortant\"},\"type\":\"line\",\"mode\":\"normal\",\"valueAxis\":\"ValueAxis-1\"}],\"legendPosition\":\"right\"},\"aggs\":[{\"id\":\"1\",\"enabled\":true,\"type\":\"sum\",\"schema\":\"metric\",\"params\":{\"field\":\"system.network.in.bytes\"}},{\"id\":\"2\",\"enabled\":true,\"type\":\"sum\",\"schema\":\"metric\",\"params\":{\"field\":\"system.network.out.bytes\"}},{\"id\":\"3\",\"enabled\":true,\"type\":\"date_histogram\",\"schema\":\"segment\",\"params\":{\"field\":\"@timestamp\",\"interval\":\"auto\"}},{\"id\":\"4\",\"enabled\":true,\"type\":\"terms\",\"schema\":\"group\",\"params\":{\"field\":\"system.network.name\",\"size\":5,\"order\":\"desc\",\"orderBy\":\"1\"}}]}",
    "uiStateJSON": "{}",
    "description": "Trafic entrant/sortant cumule, une courbe par interface reseau.",
    "kibanaSavedObjectMeta": {
      "searchSourceJSON": "{\"query\":{\"query\":\"agent.type: metricbeat and metricset.name: network\",\"language\":\"kuery\"},\"filter\":[],\"indexRefName\":\"kibanaSavedObjectMeta.searchSourceJSON.index\"}"
    }
  }
}
JSONEOF

# ===================================================================
# FILEBEAT - comptage par machine + repartition par source de log
# ===================================================================

cat > "${WORKDIR}/viz-events-host.json" << 'JSONEOF'
{
  "attributes": {
    "title": "Evenements Filebeat par machine",
    "visState": "{\"title\":\"Evenements Filebeat par machine\",\"type\":\"histogram\",\"params\":{\"grid\":{\"categoryLines\":false},\"categoryAxes\":[{\"id\":\"CategoryAxis-1\",\"type\":\"category\",\"position\":\"bottom\",\"show\":true,\"title\":{\"text\":\"@timestamp\"}}],\"valueAxes\":[{\"id\":\"ValueAxis-1\",\"name\":\"LeftAxis-1\",\"type\":\"value\",\"position\":\"left\",\"show\":true,\"title\":{\"text\":\"Nombre d'evenements\"}}],\"seriesParams\":[{\"data\":{\"id\":\"1\",\"label\":\"Count\"},\"type\":\"histogram\",\"mode\":\"stacked\",\"valueAxis\":\"ValueAxis-1\"}],\"legendPosition\":\"right\"},\"aggs\":[{\"id\":\"1\",\"enabled\":true,\"type\":\"count\",\"schema\":\"metric\",\"params\":{}},{\"id\":\"2\",\"enabled\":true,\"type\":\"date_histogram\",\"schema\":\"segment\",\"params\":{\"field\":\"@timestamp\",\"interval\":\"auto\"}},{\"id\":\"3\",\"enabled\":true,\"type\":\"terms\",\"schema\":\"group\",\"params\":{\"field\":\"host.hostname\",\"size\":10,\"order\":\"desc\",\"orderBy\":\"1\"}}]}",
    "uiStateJSON": "{}",
    "description": "Volume de lignes de log collectees, empile par machine.",
    "kibanaSavedObjectMeta": {
      "searchSourceJSON": "{\"query\":{\"query\":\"agent.type: filebeat\",\"language\":\"kuery\"},\"filter\":[],\"indexRefName\":\"kibanaSavedObjectMeta.searchSourceJSON.index\"}"
    }
  }
}
JSONEOF

cat > "${WORKDIR}/viz-events-source.json" << 'JSONEOF'
{
  "attributes": {
    "title": "Repartition par source de log",
    "visState": "{\"title\":\"Repartition par source de log\",\"type\":\"pie\",\"params\":{\"type\":\"pie\",\"addTooltip\":true,\"addLegend\":true,\"legendPosition\":\"right\",\"isDonut\":true,\"labels\":{\"show\":false}},\"aggs\":[{\"id\":\"1\",\"enabled\":true,\"type\":\"count\",\"schema\":\"metric\",\"params\":{}},{\"id\":\"2\",\"enabled\":true,\"type\":\"terms\",\"schema\":\"segment\",\"params\":{\"field\":\"log.file.path\",\"size\":10,\"order\":\"desc\",\"orderBy\":\"1\"}}]}",
    "uiStateJSON": "{}",
    "description": "Part de chaque fichier/journal source dans le volume total Filebeat.",
    "kibanaSavedObjectMeta": {
      "searchSourceJSON": "{\"query\":{\"query\":\"agent.type: filebeat\",\"language\":\"kuery\"},\"filter\":[],\"indexRefName\":\"kibanaSavedObjectMeta.searchSourceJSON.index\"}"
    }
  }
}
JSONEOF

for entry in "visualization:metricbeat-cpu-host:${WORKDIR}/viz-cpu.json:CPU par machine" \
             "visualization:metricbeat-memory-host:${WORKDIR}/viz-memory.json:Memoire par machine" \
             "visualization:metricbeat-network-iface:${WORKDIR}/viz-network.json:Reseau par interface" \
             "visualization:filebeat-events-host:${WORKDIR}/viz-events-host.json:Evenements par machine" \
             "visualization:filebeat-events-source:${WORKDIR}/viz-events-source.json:Repartition par source"; do
  IFS=':' read -r type id file label <<< "$entry"
  # Injecte la reference au data view via python3 (deja une dependance
  # du projet, cf. bin/history.sh/bin/queue_stats.sh) plutot que jq,
  # jamais garanti present sur une image minimale.
  python3 - "$file" "$INDEX_REF" << 'PYEOF'
import json, sys
path, refs_raw = sys.argv[1], sys.argv[2]
with open(path) as f:
    obj = json.load(f)
obj["references"] = json.loads(refs_raw)
with open(path, "w") as f:
    json.dump(obj, f)
PYEOF
  post_object "$type" "$id" "$file" "$label"
done

# ===================================================================
# DEUX TABLEAUX DE BORD - un par famille
# ===================================================================

cat > "${WORKDIR}/dash-metricbeat.json" << 'JSONEOF'
{
  "attributes": {
    "title": "Monitoring systeme (Metricbeat)",
    "description": "CPU, memoire et reseau des machines surveillees - style EyesOfNetwork.",
    "hits": 0,
    "panelsJSON": "[{\"version\":\"8.19.14\",\"type\":\"visualization\",\"gridData\":{\"x\":0,\"y\":0,\"w\":48,\"h\":15,\"i\":\"1\"},\"panelIndex\":\"1\",\"embeddableConfig\":{},\"panelRefName\":\"panel_1\"},{\"version\":\"8.19.14\",\"type\":\"visualization\",\"gridData\":{\"x\":0,\"y\":15,\"w\":24,\"h\":15,\"i\":\"2\"},\"panelIndex\":\"2\",\"embeddableConfig\":{},\"panelRefName\":\"panel_2\"},{\"version\":\"8.19.14\",\"type\":\"visualization\",\"gridData\":{\"x\":24,\"y\":15,\"w\":24,\"h\":15,\"i\":\"3\"},\"panelIndex\":\"3\",\"embeddableConfig\":{},\"panelRefName\":\"panel_3\"}]",
    "optionsJSON": "{\"useMargins\":true,\"hidePanelTitles\":false}",
    "version": 1,
    "timeRestore": true,
    "timeTo": "now",
    "timeFrom": "now-24h",
    "kibanaSavedObjectMeta": {
      "searchSourceJSON": "{\"query\":{\"query\":\"\",\"language\":\"kuery\"},\"filter\":[]}"
    }
  },
  "references": [
    {"name": "panel_1", "type": "visualization", "id": "metricbeat-cpu-host"},
    {"name": "panel_2", "type": "visualization", "id": "metricbeat-memory-host"},
    {"name": "panel_3", "type": "visualization", "id": "metricbeat-network-iface"}
  ]
}
JSONEOF
post_object "dashboard" "monitoring-metricbeat" "${WORKDIR}/dash-metricbeat.json" "Dashboard Monitoring systeme (Metricbeat)"

cat > "${WORKDIR}/dash-filebeat.json" << 'JSONEOF'
{
  "attributes": {
    "title": "Activite journaux (Filebeat)",
    "description": "Comptage des evenements collectes - par machine et par source.",
    "hits": 0,
    "panelsJSON": "[{\"version\":\"8.19.14\",\"type\":\"visualization\",\"gridData\":{\"x\":0,\"y\":0,\"w\":48,\"h\":15,\"i\":\"1\"},\"panelIndex\":\"1\",\"embeddableConfig\":{},\"panelRefName\":\"panel_1\"},{\"version\":\"8.19.14\",\"type\":\"visualization\",\"gridData\":{\"x\":0,\"y\":15,\"w\":48,\"h\":15,\"i\":\"2\"},\"panelIndex\":\"2\",\"embeddableConfig\":{},\"panelRefName\":\"panel_2\"}]",
    "optionsJSON": "{\"useMargins\":true,\"hidePanelTitles\":false}",
    "version": 1,
    "timeRestore": true,
    "timeTo": "now",
    "timeFrom": "now-24h",
    "kibanaSavedObjectMeta": {
      "searchSourceJSON": "{\"query\":{\"query\":\"\",\"language\":\"kuery\"},\"filter\":[]}"
    }
  },
  "references": [
    {"name": "panel_1", "type": "visualization", "id": "filebeat-events-host"},
    {"name": "panel_2", "type": "visualization", "id": "filebeat-events-source"}
  ]
}
JSONEOF
post_object "dashboard" "activite-filebeat" "${WORKDIR}/dash-filebeat.json" "Dashboard Activite journaux (Filebeat)"

rm -rf "$WORKDIR"

[ $FAILED -eq 0 ] && { echo "[KB_031_MONITORING_DASHBOARDS] OK."; exit 0; }
exit 1
