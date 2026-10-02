# beac_scenario_tools.sh - scenario metier "stage BEAC" : simule deux
# sources de journaux d'une banque centrale, chacune ECRITE DANS UN
# FICHIER (jamais un appel direct a l'API Elasticsearch, contrairement
# a jobs/lib/test_data_tools.sh) - c'est Logstash (LS_020/LS_024) qui
# lit ces fichiers et les indexe, exactement comme une vraie chaine de
# collecte le ferait pour une application reelle qui journalise.
#
# AJOUTE LE 2026-09-13 (demande explicite : "l'etudiante fait son stage
# a la BEAC... on doit voir des index dans Kibana propres a ca... quand
# l'enregistrement de log se fait dans le fichier on doit le voir
# apparaitre dans son index dans Kibana").
#
# Deux jeux de donnees, deux fichiers, deux index - jamais melanges :
#   - LCB-FT (Lutte Contre le Blanchiment de Capitaux et le Financement
#     du Terrorisme) : detections de nature variee.
#   - CyrielleMoney : application simulee de transfert d'argent
#     (national/international), journaux au format d'un serveur
#     d'application Glassfish.
#
# CHOIX ASSUME : les zones geographiques "a risque" utilisees dans les
# detections LCB-FT sont des codes FICTIFS ("ZONE-RISQUE-A/B/C"),
# jamais un vrai nom de pays - une donnee de demo ne doit jamais laisser
# croire a une affirmation reelle sur le statut d'embargo/sanction d'un
# pays reel. Les pays CEMAC cites ailleurs (transferts normaux) sont de
# la geographie neutre, pas une accusation.
#
# Meme champ distinctif "wef_test_seed": true que jobs/lib/test_data_tools.sh.

# seed_lcbft_detections_file <log_file> <min_count> <max_count> <interval_sec>
# Ajoute (append, jamais tronque) un nombre de detections TIRE AU HASARD
# entre <min_count> et <max_count> a chaque appel - demande explicite :
# "montrer qu'on peut detecter 1 enregistrement et a certains moments
# voir meme 5 d'un coup". Une ligne JSON par detection, <interval_sec>
# de pause reelle entre chaque - Logstash (file input, LS_020) les
# reprend en direct au fil de l'eau, comme un vrai "tail -f".
seed_lcbft_detections_file() {
  local log_file="$1" min_count="$2" max_count="$3" interval="$4"
  mkdir -p "$(dirname "$log_file")"
  touch "$log_file"
  chmod 644 "$log_file"
  LOG_FILE="$log_file" MIN_COUNT="$min_count" MAX_COUNT="$max_count" INTERVAL="$interval" \
  python3 << 'PYEOF'
import os, json, random, time, uuid, datetime

log_file = os.environ['LOG_FILE']
min_count = int(os.environ['MIN_COUNT']); max_count = int(os.environ['MAX_COUNT'])
interval = float(os.environ['INTERVAL'])
count = random.randint(min_count, max_count)

detection_types = [
    "FRANCHISSEMENT_SEUIL_ESPECES", "STRUCTURATION_FRACTIONNEMENT",
    "TRANSFERT_ZONE_RISQUE", "CLIENT_PPE", "VIREMENTS_RAPIDES_SUCCESSIFS",
    "INCOHERENCE_PROFIL_CLIENT", "SUSPICION_FAUX_DOCUMENTS",
    "MULTIPLICATION_BENEFICIAIRES", "RETRAIT_ATYPIQUE_GUICHET",
    "TRANSACTION_LISTE_SURVEILLANCE_INTERNE",
]
niveaux = ["FAIBLE"] * 3 + ["MOYEN"] * 4 + ["ELEVE"] * 2 + ["CRITIQUE"] * 1
statuts = ["OUVERT"] * 4 + ["EN_ANALYSE"] * 3 + ["ESCALADE"] * 2 + ["CLOTURE"] * 1
zones_cemac = ["Cameroun", "Tchad", "Congo", "Gabon", "Guinee Equatoriale", "Republique Centrafricaine"]
zones_risque_fictives = ["ZONE-RISQUE-A", "ZONE-RISQUE-B", "ZONE-RISQUE-C"]
analystes = ["A. NGONO", "B. MBARGA", "C. IYODI", "D. BEYALA", "E. FOUDA"]

inserted = 0
with open(log_file, 'a') as f:
    for i in range(count):
        dtype = random.choice(detection_types)
        risque_types = ("TRANSFERT_ZONE_RISQUE", "TRANSACTION_LISTE_SURVEILLANCE_INTERNE")
        zone = random.choice(zones_risque_fictives) if dtype in risque_types else random.choice(zones_cemac)
        devise = random.choice(["XAF"] * 6 + ["EUR"] * 2 + ["USD"] * 2)
        now = datetime.datetime.utcnow().isoformat() + "Z"
        doc = {
            "timestamp": now,
            "application": "LCB-FT-BEAC",
            "detection_id": f"LCBFT-{uuid.uuid4().hex[:10].upper()}",
            "detection_type": dtype,
            "niveau_risque": random.choice(niveaux),
            "client_ref": f"CLI-{random.randint(100000, 999999)}",
            "compte_ref": f"CPT-{random.randint(1000000000, 9999999999)}",
            "montant": round(random.uniform(500000, 50000000), 2),
            "devise": devise,
            "zone_geographique": zone,
            "statut_dossier": random.choice(statuts),
            "analyste_assigne": random.choice(analystes),
            "full_log": f"Detection LCB-FT #{i + 1}/{count} - {dtype} - risque {zone}",
            "wef_test_seed": True,
        }
        f.write(json.dumps(doc) + "\n")
        f.flush()
        inserted += 1
        print(f"[seed_lcbft] {inserted}/{count} detection(s) ecrite(s) dans {log_file} ({dtype})")
        if i + 1 < count:
            time.sleep(interval)

print(f"ECRIT={inserted}")
PYEOF
}

# seed_monetic_collection_file <log_file> <min_count> <max_count> <interval_sec>
# AJOUTE LE 2026-09-30 (remplace l'ancien scenario "contournement par un
# pays tiers", annule sur demande explicite) - repond a l'objectif
# Architecture desormais "Fraude sur compte dormant" (Applications >
# Conformite financiere) et au nouvel objectif "Collecte des donnees
# financieres et monetiques" (remplace "Supervision applicative unifiee"/
# AnkrrWEF, retire du dossier). Meme fichier, meme index que
# seed_lcbft_detections_file.
#
# REFONDU LE 2026-10-01 (demande explicite : "l'alerte ne doit pas monter
# directement... c'est quand on va entrer manuellement la ligne dans le
# fichier qu'une fois Logstash va faire la correlation") : cette fonction
# N'ECRIT PLUS DE JUGEMENT - elle ecrit des transactions BRUTES
# (type_evenement=transaction_brute, aucun detection_type/niveau_alerte/
# statut_compte/statut_traitement). La correlation reelle (compte dans
# DORMANT_ACCOUNTS + operation REUSSIE => fraude) est desormais faite par
# Logstash lui-meme (jobs/LS_023C_BEAC_DORMANT_DICT.sh +
# jobs/LS_023D_BEAC_DORMANT_CORRELATION.sh, filtre translate + condition)
# - Kibana affiche enfin le resultat d'une VRAIE corrélation, jamais plus
# une etiquette deja collee par ce script. L'ancien role "simule un
# logiciel SIRON/AML" est donc retire d'ici : c'est desormais LE PIPELINE
# ELK (Logstash) qui joue ce role, pas ce job d'alimentation.
#
# PATTERN DE FRAUDE ILLUSTRE (inchange) : un compte marque DORMANT (aucun
# mouvement depuis des mois) subit une operation qui REUSSIT - le signal
# n'est pas la tentative, c'est la reussite sur un compte cense etre
# inactif. La garantie reste la MEME (DORMANT_ACCOUNTS, vars.conf) : ce
# job ecrit toujours une transaction REUSSIE sur chaque compte declare
# dormant a chaque execution - seule la QUALIFICATION de cette
# transaction (fraude ou non) n'est plus decidee ici.
#
# CHAMPS AJOUTES LE 2026-09-30/10-01 (qui a fait la transaction, depuis
# ou) : titulaire_compte (nom simule) et, pour le canal GUICHET,
# agent_guichet (qui a traite l'operation) - rendent la ligne manuelle
# lisible a l'ecran au moment ou elle est tapee en demo.
seed_monetic_collection_file() {
  local log_file="$1" min_count="$2" max_count="$3" interval="$4" dormant_accounts="$5"
  mkdir -p "$(dirname "$log_file")"
  touch "$log_file"
  chmod 644 "$log_file"
  LOG_FILE="$log_file" MIN_COUNT="$min_count" MAX_COUNT="$max_count" INTERVAL="$interval" DORMANT_ACCOUNTS="$dormant_accounts" \
  python3 << 'PYEOF'
import os, json, random, time, uuid, datetime

log_file = os.environ['LOG_FILE']
min_count = int(os.environ['MIN_COUNT']); max_count = int(os.environ['MAX_COUNT'])
interval = float(os.environ['INTERVAL'])
dormant_accounts = [a.strip() for a in os.environ.get('DORMANT_ACCOUNTS', '').split(',') if a.strip()]
noise_count = random.randint(min_count, max_count)

canaux = ["DAB", "GAB", "TPE", "GUICHET", "VIREMENT_EN_LIGNE"]
titulaires = ["J. MBALLA", "S. ATANGANA", "P. ONDOA", "R. EKANI", "M. NDJOCK", "L. BIYICK"]
agents_guichet = ["Guichet 1 - A. TALLA", "Guichet 2 - C. NGO BALLA", "Guichet 3 - D. FOTSO"]
localisations_physiques = ["Agence Douala-Bonanjo", "Agence Yaounde-Bastos", "DAB Aeroport Douala",
                            "TPE Supermarche CentreVille", "GAB Marche Central", "TPE Station-service Akwa"]

def make_doc(compte_ref, montant_range):
    canal = random.choice(canaux)
    if canal == "VIREMENT_EN_LIGNE":
        localisation = "Application mobile (en ligne)"
        agent_guichet = "N/A"
    elif canal == "GUICHET":
        localisation = random.choice(["Agence Douala-Bonanjo", "Agence Yaounde-Bastos"])
        agent_guichet = random.choice(agents_guichet)
    else:
        localisation = random.choice(localisations_physiques)
        agent_guichet = "N/A"
    montant = round(random.uniform(*montant_range), 2)
    now = datetime.datetime.utcnow().isoformat() + "Z"
    # AUCUN detection_type/niveau_risque/niveau_alerte/statut_compte/
    # statut_dossier/statut_traitement ici - transaction brute uniquement,
    # la qualification est le travail reel de Logstash (translate filter).
    return {
        "timestamp": now,
        "application": "LCB-FT-BEAC",
        "type_evenement": "transaction_brute",
        "transaction_id": f"TXN-{uuid.uuid4().hex[:10].upper()}",
        "client_ref": f"CLI-{random.randint(100000, 999999)}",
        "compte_ref": compte_ref,
        "titulaire_compte": random.choice(titulaires),
        "canal": canal,
        "localisation": localisation,
        "agent_guichet": agent_guichet,
        "montant": montant,
        "devise": "XAF",
        "resultat_operation": "REUSSI",
        "full_log": f"Transaction {canal} REUSSIE - compte {compte_ref} - {montant} XAF - {localisation}",
        "wef_test_seed": True,
    }

total = len(dormant_accounts) + noise_count
inserted = 0
with open(log_file, 'a') as f:
    # 1) Une transaction REUSSIE GARANTIE par compte declare dans
    #    DORMANT_ACCOUNTS - le statut DORMANT/fraude n'est plus ecrit ici,
    #    c'est Logstash qui le determinera en comparant compte_ref a la
    #    liste reelle (meme garantie de resultat, autre endroit du pipeline).
    for compte_ref in dormant_accounts:
        doc = make_doc(compte_ref, (10000, 500000))
        f.write(json.dumps(doc) + "\n")
        f.flush()
        inserted += 1
        print(f"[seed_monetic] {inserted}/{total} transaction(s) ecrite(s) dans {log_file} (compte {compte_ref} - correlation Logstash a suivre)")
        if inserted < total:
            time.sleep(interval)
    # 2) Volume normal autour du signal - comptes aleatoires (hors liste
    #    DORMANT_ACCOUNTS), Logstash les classera ACTIF par defaut (fallback).
    for i in range(noise_count):
        compte_ref = f"CPT-{random.randint(1000000000, 9999999999)}"
        doc = make_doc(compte_ref, (2000, 150000))
        f.write(json.dumps(doc) + "\n")
        f.flush()
        inserted += 1
        print(f"[seed_monetic] {inserted}/{total} transaction(s) ecrite(s) dans {log_file} (collecte normale, compte {compte_ref})")
        if inserted < total:
            time.sleep(interval)

print(f"ECRIT={inserted}")
print(f"COMPTES_DORMANTS_GARANTIS={len(dormant_accounts)}")
PYEOF
}

# seed_cyriellemoney_transfers_file <log_file> <count> <interval_sec>
# Ajoute (append) <count> evenements de transfert CyrielleMoney, une
# ligne JSON a la fois, <interval_sec> de pause reelle entre chaque -
# meme mecanique de visibilite en direct que seed_lcbft_detections_file.
seed_cyriellemoney_transfers_file() {
  local log_file="$1" count="$2" interval="$3"
  mkdir -p "$(dirname "$log_file")"
  touch "$log_file"
  chmod 644 "$log_file"
  LOG_FILE="$log_file" COUNT="$count" INTERVAL="$interval" \
  python3 << 'PYEOF'
import os, json, random, time, uuid, datetime

log_file = os.environ['LOG_FILE']
count = int(os.environ['COUNT']); interval = float(os.environ['INTERVAL'])

services = ["cyriellemoney-transfert", "cyriellemoney-change", "cyriellemoney-encaissement"]
app_servers = ["glassfish-01", "glassfish-02"]
pays_cemac = ["Cameroun", "Tchad", "Congo", "Gabon", "Guinee Equatoriale", "Republique Centrafricaine"]
pays_internationaux = ["France", "Chine", "Etats-Unis", "Belgique", "Emirats Arabes Unis"]
statuts = ["SUCCESS"] * 7 + ["FAILED"] * 2 + ["PENDING"] * 1
http_by_status = {"SUCCESS": 200, "FAILED": 500, "PENDING": 202}

inserted = 0
with open(log_file, 'a') as f:
    for i in range(count):
        national = random.random() < 0.5
        if national:
            pays_emetteur = pays_beneficiaire = random.choice(pays_cemac)
            devise = "XAF"
        else:
            pays_emetteur = random.choice(pays_cemac)
            pays_beneficiaire = random.choice(pays_internationaux)
            devise = random.choice(["XAF", "EUR", "USD"])
        statut = random.choice(statuts)
        now = datetime.datetime.utcnow().isoformat() + "Z"
        doc = {
            "timestamp": now,
            "application": "CyrielleMoney",
            "transfer_id": f"CM-{uuid.uuid4().hex[:12].upper()}",
            "type_transfert": "NATIONAL" if national else "INTERNATIONAL",
            "service": random.choice(services),
            "app_server": random.choice(app_servers),
            "pays_emetteur": pays_emetteur,
            "pays_beneficiaire": pays_beneficiaire,
            "montant": round(random.uniform(5000, 5000000), 2),
            "devise": devise,
            "statut": statut,
            "http_status": http_by_status[statut],
            "temps_reponse_ms": random.randint(30, 1500),
            "full_log": f"CyrielleMoney transfert #{i + 1}/{count} - {'NATIONAL' if national else 'INTERNATIONAL'} - {statut}",
            "wef_test_seed": True,
        }
        f.write(json.dumps(doc) + "\n")
        f.flush()
        inserted += 1
        print(f"[seed_cyriellemoney] {inserted}/{count} transfert(s) ecrit(s) dans {log_file}")
        if i + 1 < count:
            time.sleep(interval)

print(f"ECRIT={inserted}")
PYEOF
}
