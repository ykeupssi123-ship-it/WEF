> **Lecture optionnelle / approfondie.** Ce document est le journal technique
> complet du projet : chaque bug réel rencontré, sa cause exacte, son
> diagnostic et son correctif, dans l'ordre chronologique. Il n'est **pas**
> nécessaire pour installer ou exploiter le produit — voir
> [`README.md`](../README.md) et [`GUIDE_EXPLOITATION.md`](../GUIDE_EXPLOITATION.md)
> à la racine pour ça. Gardé ici pour la profondeur d'ingénierie qu'il
> démontre (utile pour une soutenance, un audit, ou pour quiconque doit un
> jour modifier ce code en connaissance de cause).

# WAZ_ELK_FACTORY - Scripts d'automatisation (241 jobs Linux + kit Windows)

Suite de `wazuh_factory_2/` (modele Manager/Agent), ce dossier scripte le
blueprint `factory_core_blueprint_v13.xlsx` (229 jobs : PKI, INFRA, DIST,
Elasticsearch, Logstash, Kibana, Filebeat, Metricbeat, Wazuh) + 2 jobs de
sauvegarde optionnels (ES_062/ES_063) + 6 jobs d'agent Wazuh Linux
(WAG_001-006, voir "Agents" plus bas) + 1 job de dimensionnement JVM
wazuh-indexer (WAZ_013B) + 3 jobs d'authentification Kibana/Wazuh
Dashboard optionnels (WAZ_017B/C/E, ajoutes le 2026-08-11, fusionnes le
meme jour en un job de configuration unique, voir section
"Authentification Kibana / Wazuh Dashboard (SSO)" plus bas) - tous
ajoutes hors blueprint d'origine.

**241 scripts Linux + un kit Windows separe (`jobs_windows/`, 20 scripts
PowerShell : agent Wazuh + Filebeat + Metricbeat) sont ecrits, verifies
et audites.** Reste l'execution reelle contre les VM (192.168.50.128 /
.129) et contre de vraies machines Windows. Execution reelle en cours sur
VM1 (ELK_HOST) au 2026-08-11 - voir section "Dimensionnement ressources"
pour le profil RAM/disque reduit utilise sur cette VM de demo.

## Agents (comment les donnees arrivent aux services centraux)

Trois "agents" au sens large, chacun avec son propre flux :

- **Agent Wazuh** pousse les evenements de securite vers wazuh-manager
  (port 1514/1515) - Logstash n'intervient PAS dans ce flux.
- **Filebeat** pousse des logs (fichiers sous Linux, Journal des
  evenements Windows sous Windows) vers Logstash (port 5044).
- **Metricbeat** pousse des metriques systeme (CPU/RAM/disque/reseau)
  vers Logstash (port 5044), meme port que Filebeat.

Sans agent deploye quelque part, rien n'alimente les services centraux
- c'est le point que vous aviez souleve, corrige.

### Linux

Un seul `ROLE=AGENT_HOST` pour toute machine qui n'est pas VM1, plus
une liste `AGENT_COMPONENTS` (dans `vars.conf`) qui dit QUELS agents
tournent sur CETTE machine precise, parmi `FILEBEAT`, `METRICBEAT`,
`WAZUH_AGENT` (+ `HOSTNAME_RENAME`, optionnel/isole). Les 3 peuvent
cohabiter sur la MEME machine (c'est le cas de VM2 par defaut :
`AGENT_COMPONENTS="FILEBEAT,METRICBEAT,WAZUH_AGENT,HOSTNAME_RENAME"`)
ou etre repartis sur des machines differentes - a vous de choisir par
machine, ex. un hote Linux supplementaire qui ne doit surveiller que
la securite : `AGENT_COMPONENTS="WAZUH_AGENT"`.

- `WAG_001`-`006` (agent Wazuh, RPM ou DEB detecte automatiquement).
- `FB_001`-`023` / `MB_001`-`022` (Filebeat/Metricbeat).

Dans tous les cas : copiez le dossier sur l'hote, `ROLE=AGENT_HOST`
dans `vars.conf`, choisissez `AGENT_COMPONENTS`, `AGENT_NAME` unique
par machine, lancez `./orchestrator.sh`.

### Windows (`jobs_windows/`)

Un seul kit PowerShell (execution en administrateur) couvre les 3
composants, **activables independamment par machine** via
`$EnabledComponents` dans `vars.ps1` (ex: `@("FILEBEAT")` seul si une
machine ne doit avoir que Filebeat) :

- `WAW_001`-`006` : agent Wazuh (MSI officiel, service `WazuhSvc`).
- `FBW_001`-`007` : Filebeat (archive ZIP officielle, service
  `filebeat`, lit le Journal des evenements Windows - Application/
  System/Security - via l'input `winlog`).
- `MBW_001`-`007` : Metricbeat (archive ZIP officielle, service
  `metricbeat`, module `system` : cpu/memoire/reseau/disque/process).

`FBW_004`/`MBW_004` verifient la presence du certificat de la CA
d'usine (`$PKI_CA_LOCAL_PATH`, `C:\ProgramData\wef-pki\factory_ca.crt`
par defaut) AVANT de configurer la sortie TLS vers Logstash - il n'y a
pas de canal automatique (SSH/SCP) depuis ce kit vers VM1, contrairement
a `DIST_001` cote Linux : vous deposez vous-meme ce fichier (recupere
depuis VM1) avant de lancer, sinon le job s'arrete avec des
instructions claires plutot que d'improviser. Choix delibere : plus
simple et plus fiable qu'automatiser un canal SSH que je ne peux pas
tester depuis ce bac a sable (pas de Windows/PowerShell disponibles ici).

`FACTORY_HOST_IP` (`vars.ps1`) doit pointer vers VM1 - le manager/
Logstash n'ont besoin d'aucune modification pour accepter de nouveaux
agents ou flux Beats, tout est deja pret a les recevoir.

**Point de vigilance signale mais non teste** : `orchestrator_windows.ps1`
a ete relu et verifie (accolades/parentheses equilibrees, un bug reel
deja corrige - voir plus bas), mais je n'ai pas de PowerShell dans ce
bac a sable pour l'executer reellement. A tester sur une vraie machine
Windows avant un usage en conditions reelles.

## Rapport d'execution et comportement en cas d'echec

Chaque lancement de `orchestrator.sh` (ou `orchestrator_windows.ps1`)
ecrit desormais `state/RAPPORT_EXECUTION.txt` a la fin, QUELLE QUE SOIT
L'ISSUE : jobs termines avec succes, job en echec le cas echeant, et
jobs jamais atteints. Teste reellement (succes et echec simules).

**Comportement en cas d'echec d'un job : l'orchestrateur s'arrete**
(fail-fast), il ne saute pas au job suivant. Choix deliberer : la
plupart des jobs suivants dependent d'un etat que le job en echec etait
cense produire (config ecrite, service demarre...) - continuer risque
d'empiler des jobs sur une base deja cassee. Chaque machine (VM1, VM2,
chaque hote d'agent Linux ou Windows) execute SA PROPRE instance de
l'orchestrateur : un echec sur une machine n'arrete jamais les autres,
qui tournent completement independamment.

## Comment les services trouvent les cles PKI

Un seul repertoire local par machine, `${PKI_DIR}` (defaut
`/etc/pki/factory/certs`), et TOUS les jobs consommateurs (ES, LS, KB,
FB, MB, WAZ) lisent exactement les memes 3 fichiers a cet emplacement -
jamais un chemin en dur, verifie par grep sur les 231 scripts :

- `${PKI_DIR}/factory_ca.crt` - certificat de la CA (pour verifier qui
  presente un certificat)
- `${PKI_DIR}/factory_server.key` - cle privee du certificat serveur
- `${PKI_DIR}/factory_fullchain.pem` - certificat serveur + CA concatenes

**Sur VM1 (ELK_HOST)** : PKI_001-011 remplissent ce repertoire une
fois: ES/LS/KB/WAZ tournent sur la meme machine, donc y accedent
directement, sans aucune copie.

**Sur VM2 (BEATS_HOST)** : Filebeat/Metricbeat sont sur une machine
physiquement differente, qui n'a par definition pas ce repertoire tant
que rien ne l'y a copie. C'est le role de `DIST_001` : au premier
lancement de l'orchestrateur sur VM2, il va chercher `factory_ca.crt`
sur VM1 par SCP/SSH (cle SSH recommandee, mot de passe accepte en
secours) et le depose localement dans `${PKI_DIR}` sur VM2. Filebeat et
Metricbeat n'ont besoin QUE du certificat de la CA (pas d'une cle
privee) puisqu'ils sont clients TLS, pas serveurs.

**Autorisation locale** : sur chaque machine, un groupe systeme dedie
`factory_crypto` (`CRYPTO_GROUP` dans `vars.conf`) porte les droits de
lecture. Sur VM1, `PKI_001` cree le groupe et `PKI_011` verrouille tout
le repertoire en `640 root:factory_crypto` a la fin du chantier. Sur
VM2, `FB_006`/`MB_006` creent ce meme groupe localement (les groupes
Linux ne traversent pas le reseau) et y ajoutent les comptes
`filebeat`/`metricbeat`. Chaque service a donc sa propre autorisation
explicite, jamais un acces global.

**VM2 fait tourner les 3 agents ensemble** (Filebeat + Metricbeat +
agent Wazuh, `AGENT_COMPONENTS="FILEBEAT,METRICBEAT,WAZUH_AGENT"`) :
c'est la repartition reelle de cette topologie a 2 VM, VM1 = PKI+ELK+
Wazuh-manager, VM2 = les 3 agents. L'agent Wazuh (`WAG_*`) utilise son
propre mecanisme d'enrolement (`client.keys` via le port 1515), separe
de la PKI TLS ci-dessus qui ne concerne que Filebeat/Metricbeat/Logstash.
Rien n'empeche de repartir les 3 agents sur des machines differentes
dans un autre environnement : c'est justement le role
d'`AGENT_COMPONENTS`, choisi independamment par machine.

## PKI interne ou PKI d'entreprise deja existante (`PKI_MODE`)

Nouvelle variable dans `vars.conf` : `PKI_MODE`.

- `PKI_MODE=generate` (defaut, comportement actuel) : `PKI_003` a
  `PKI_007` fabriquent leur propre autorite de certification et
  signent eux-memes le certificat serveur.
- `PKI_MODE=external` : ces memes jobs ne generent plus rien et
  n'exigent jamais la cle privee d'une CA (une PKI d'entreprise ne la
  partage jamais, et ce n'est pas necessaire). Ils attendent que ces 3
  fichiers soient deja deposes dans `${PKI_DIR}` avant le lancement de
  l'orchestrateur : `factory_ca.crt`, `factory_server.key`,
  `factory_server.crt`. Si l'un manque, le job s'arrete avec un message
  clair au lieu d'improviser une PKI a nous.

**Aucun autre job n'a besoin d'etre reecrit ni rejoue differemment**
quel que soit le mode : ES/LS/KB/FB/MB/WAZ lisent toujours les memes 3
fichiers a la meme adresse. Verifie par un test reel avec une CA
"externe" simulee (cle privee jamais donnee a nos scripts, cree hors
de `PKI_DIR`) : les 6 jobs PKI la detectent, ne la touchent pas, et
`openssl verify` confirme que le certificat reste valide et intact
apres le passage des jobs.

## Format des fichiers (Windows -> Oracle Linux)

Tous les scripts sont en pur LF (pas de CRLF), sans BOM, shebang
`#!/bin/bash` propre - verifie fichier par fichier avec `file` et
`cat -A`. Aucun probleme de conversion attendu au transfert vers Oracle
Linux. Seul point a faire systematiquement apres tout transfert (copie
reseau, cle USB, etc.) : redonner les droits d'execution, deja couvert
par la commande `chmod +x *.sh jobs/*.sh` ci-dessous.

**CORRECTIF 2026-09-02 (incident reel, deploiement VM ELK_HOST)** :
la commande etait auparavant `chmod +x orchestrator.sh jobs/*.sh` -
elle ne couvrait que `orchestrator.sh` a la racine, oubliant les
autres scripts racine executes directement par l'operateur ou par
orchestrator.sh lui-meme (`notifier.sh`, `statut_live.sh`,
`historique_job.sh`, `reprise_deploiement.sh`...). Consequence reelle
observee : `./notifier.sh --test` a echoue avec "Permission non
accordee" juste apres un clone frais. Corrige en `chmod +x *.sh
jobs/*.sh`, qui couvre tous les scripts racine en plus de `jobs/`.

**Meme regle d'or que wazuh_factory_2** : aucun script ne contient de
valeur en dur (IP, nom, chemin specifique). Tout vient de `vars.conf`.

## Topologie a 2 VM

- **VM1 (ROLE=ELK_HOST)** : PKI + Elasticsearch + Logstash + Kibana + Wazuh-manager
- **VM2 (ROLE=AGENT_HOST, AGENT_COMPONENTS=FILEBEAT,METRICBEAT,WAZUH_AGENT,HOSTNAME_RENAME)** :
  les 3 agents ensemble sur la meme machine (voir "Agents" plus haut).
  N'importe quel hote Linux ou Windows supplementaire peut rejoindre le
  meme manager/Logstash avec `ROLE=AGENT_HOST` et un sous-ensemble
  different d'`AGENT_COMPONENTS`.

Avant le premier lancement, remplir dans `vars.conf` :
- `FACTORY_HOST_IP` = IP de la VM1 (utilisee par VM2 pour joindre Logstash,
  et par VM1 pour ouvrir son ecoute reseau au-dela de la boucle locale)
- `BEATS_HOST_IP` = IP de la VM2 (utilisee par VM1 pour restreindre le
  pare-feu du port 5044 a cette IP precise)

## Lancer

```bash
chmod +x *.sh jobs/*.sh
./orchestrator.sh
```

Idempotent, reprise sur erreur (memes mecanismes que wazuh_factory_2) :
chaque job termine cree `state/<OUT_CONDITION>.ok`. Un job absent du
dossier `jobs/` est simplement saute (log "SCRIPT ABSENT") sans bloquer
l'orchestrateur, ce qui permet d'avancer service par service.

## Etat d'avancement

| Service | Jobs | Scripts ecrits | Statut |
|---|---|---|---|
| PKI | 11 | 11 | Fait, teste (chaine CA + certificat + SAN verifiee openssl) |
| INFRA (renommage, isole) | 2 | 2 | Fait |
| DIST (distribution CA vers Beats) | 1 | 1 | Fait |
| Elasticsearch (ES) | 64 + 1 (ES_050B) | 65 | Fait, syntaxe + JSON verifies |
| Logstash (LS) | 36 | 36 | Fait, syntaxe verifiee (dont LS_020 patche pour l'entree Wazuh port 5000) |
| Kibana (KB) | 29 | 29 | Fait, syntaxe verifiee |
| Filebeat (FB) | 23 | 23 | Fait, syntaxe verifiee |
| Metricbeat (MB) | 22 | 22 | Fait, syntaxe verifiee |
| Wazuh (WAZ) | 40 + 1 (WAZ_013B) | 41 | Fait, syntaxe verifiee. WAZ_013B ajoute le 2026-08-11 (heap JVM wazuh-indexer, voir "Dimensionnement ressources") |
| Sauvegarde S3 (ES_062/ES_063, hors blueprint) | 2 | 2 | Fait, isoles/optionnels, desactives par defaut |
| Agent Wazuh Linux (WAG_001-006, hors blueprint) | 6 | 6 | Fait, teste (voir "Bugs trouves..." plus bas) |
| **Total (Linux)** | **238** | **238** | **Ecriture + audit + simulation fonctionnelle reelle 100% verte sur les 2 ROLE (185/185 ELK_HOST, 53/53 AGENT_HOST, voir plus bas)** |
| Kit Windows (`jobs_windows/`, hors comptage ci-dessus) | 20 | 20 | Ecrit, verifie syntaxiquement, jamais execute (pas de Windows dans ce bac a sable) |

## Verifications faites (audit, pas juste relecture)

- **229/229 lignes de `jobs_table.csv`** pointent vers un script `.sh`
  qui existe reellement (verifie par script Python, pas a l'oeil).
- **Graphe de dependances des 231 jobs** reconstruit avec `networkx` :
  acyclique, 0 dependance orpheline, 0 condition produite par deux jobs
  a la fois.
- **`bash -n` rejoue sur les 231 scripts + les 2 libs** : tous valides.
- **CRLF/BOM** : aucun fichier concerne, tout est en LF pur.
- **Idempotence rejouee reellement** (pas supposee) : `KB_014`, `LS_022`
  et `LS_024` executes 2x de suite dans un environnement simule ->
  fichiers de configuration identiques apres le 2e passage, jamais de
  bloc duplique.
- Un vrai bug trouve et corrige en cours de route : 4 scripts Wazuh
  (`WAZ_036/037/038/040`) appelaient une variable `ES_ADMIN_PASSWORD`
  inexistante dans `vars.conf` (retombait sur un mot de passe factice
  "changeme"). Corrige pour reutiliser le mecanisme `es_admin_curl()`
  deja etabli (mot de passe bootstrap arme par `ES_022`).

## Bugs trouves et corriges par simulation reelle de bout en bout (237 jobs)

Au-dela des verifications syntaxiques/DAG ci-dessus, `jobs_table.csv` +
`orchestrator.sh` ont ete rejoues REELEMENT (scripts remplaces par des
stubs `exit 0`, vrai `bash orchestrator.sh` execute, vrai fichier
`state/RAPPORT_EXECUTION.txt` lu) pour les 2 valeurs de `ROLE`. Cette
simulation a revele 3 bugs reels, invisibles a une simple relecture :

1. **`jobs_table.csv` en fin de ligne Windows (CRLF)** : le `\r`
   s'accrochait au dernier champ (`OUT_COND`) de chaque ligne. Bash
   `read` le preserve (contrairement a Python qui le normalise
   silencieusement en mode texte - c'est pour ca que l'audit Python
   precedent ne l'avait pas vu). Consequence : chaque job marquait sa
   propre reussite dans un fichier `.ok` au nom legerement corrompu,
   jamais retrouve par le job suivant censé en dependre - toute la
   chaine s'arretait apres son tout premier maillon. Corrige : fichier
   reconverti en LF pur.
2. **6 descriptions (`DESC`) contenant une virgule non echappee pour
   un lecteur CSV naif** (`ES_007`, `ES_009`, `ES_023`, `MB_007`,
   `INFRA_001`, `INFRA_002`) : correctement entre guillemets pour un
   vrai parseur CSV, mais `orchestrator.sh` lit le fichier avec un
   simple `IFS=',' read` qui ignore les guillemets - la virgule
   decalait tous les champs suivants de la ligne, corrompant
   `IN_COND`/`OUT_COND` pour ces 6 jobs et tout ce qui en dependait.
   Corrige en remplacant la virgule par un tiret dans ces 6 descriptions
   (champ purement cosmetique, utilise seulement pour le log).
3. **Dependance inter-machine impossible : `WAZ_001` (VM1) attendait
   `METRICBEAT_SENSOR_ONLINE`, produit uniquement par `MB_022` sur VM2**
   - chaque machine a son propre repertoire `state/` local, jamais
   synchronise : VM1 ne pouvait donc jamais voir ce fichier, bloquant
   la chaine Wazuh entiere (40 jobs) indefiniment. Meme famille de bug
   que celui deja trouve et corrige sur `FB_001` -> `KIBANA_HUB_ONLINE`
   plus tot dans le chantier. Corrige en faisant pointer `WAZ_001` vers
   `KIBANA_HUB_ONLINE` (produit par `KB_029`, meme machine VM1 - Wazuh
   demarre bien apres que Kibana soit pleinement disponible, ce qui a
   du sens puisque Wazuh s'integre a ses tableaux de bord).

**Verification finale** (simulation complete rejouee apres les 3
correctifs) : **`ROLE=AGENT_HOST` termine 53/53 jobs**, **`ROLE=ELK_HOST`
termine 184/184 jobs**, aucun des 237 jobs n'est plus jamais "jamais
atteint" pour son ROLE.

## Bugs trouves en DEPLOIEMENT REEL (pas juste en simulation)

Les bugs ci-dessus viennent d'une simulation a base de stubs `exit 0` -
elle prouve que l'enchainement des dependances est correct, mais ne
peut pas reveler un bug DANS la logique d'un script (un stub ne fait
jamais tourner la vraie commande). Celui-ci n'a ete trouve qu'en
executant `orchestrator.sh` pour de vrai sur une VM Oracle Linux :

4. **`rpm -q --qf` sur un paquet absent** (2026-08-12) : sur un systeme
   en langue non-anglaise, `rpm -q --qf '%{FORMAT}' paquet-absent`
   n'affiche pas une sortie vide - il ecrit un message localise du type
   *"le paquet X n'est pas installe"* directement sur stdout (constate
   en francais sur la VM du projet). Les 9 jobs d'installation
   (`ES_017`, `LS_011`, `KB_005`, `FB_004`, `MB_004`, `WAZ_010`,
   `WAZ_011`, `WAZ_012`, `WAG_003`) capturaient cette sortie dans
   `INSTALLED_VER` et testaient seulement `[ -n "$INSTALLED_VER" ]` -
   toujours vrai, meme paquet absent. Consequence reelle observee :
   Elasticsearch jamais installe (le job se contentait d'un
   avertissement puis `OK`), puis cascade d'echecs en aval
   (`elasticsearch-keystore` introuvable, `Unit elasticsearch.service
   not found`, timeout `ES_027` apres 5 minutes). Corrige : les 9 jobs
   verifient desormais l'installation via le CODE DE RETOUR de
   `rpm -q paquet` (0/1, independant de la langue du systeme) avant de
   lire `--qf`, jamais via le contenu texte. Teste sur les 3 cas
   (absent / meme version / version differente) avec un `rpm` factice
   reproduisant le message localise.

5. **`AccessDeniedException` sur `/etc/elasticsearch/certs`** (2026-08-14,
   pre-demo) : `ES_026` (demarrage d'Elasticsearch) echouait avec
   `java.nio.file.AccessDeniedException: /etc/elasticsearch/certs`.
   Cause : `ES_020.sh` recree ce dossier (`rm -rf` + `mkdir`) APRES
   qu'`ES_008.sh` ait deja mis tout `/etc/elasticsearch` a
   `elasticsearch:elasticsearch` - le `mkdir` seul le laissait
   `root:root`, et aucun job entre les deux ne reparait cette
   permission. Elasticsearch exige que tout `$ES_PATH_CONF` soit
   traversable par son utilisateur au demarrage, meme un sous-dossier
   non reference dans `elasticsearch.yml`. Corrige : `chown` ajoute
   juste apres le `mkdir` dans `ES_020.sh`.

6. **`NotEntitledException` sur les certificats SSL** (2026-08-14,
   meme session, juste apres le correctif ci-dessus) : nouvel echec
   different, `ElasticsearchSecurityException: cannot read configured
   PEM certificate_authorities [...] SSL resources should be placed in
   the [/etc/elasticsearch] directory`. Cause : Elasticsearch 8.19
   embarque un systeme de sandboxing interne ("entitlements",
   remplacant du SecurityManager Java retire du JDK) qui interdit par
   defaut la lecture de tout fichier SSL situe hors de
   `/etc/elasticsearch`, quels que soient les droits Unix - meme un
   fichier lisible par `elasticsearch:elasticsearch` est refuse si son
   chemin sort de ce dossier. `elasticsearch.yml` (`ES_023.sh`)
   pointait directement vers `PKI_DIR`, le coffre externe partage.
   Corrige : `ES_020.sh` copie desormais les 3 fichiers necessaires
   localement dans `/etc/elasticsearch/certs`, `ES_023.sh` reference
   ces copies locales. Meme reflexe applique par prudence a Logstash et
   Kibana (`local_pki_copy()` dans `lib/commun.sh`), qui referencaient
   aussi `PKI_DIR` directement.

7. **`/dev/null` transforme en fichier ordinaire, SSH inaccessible**
   (2026-08-14, pre-demo, VM1) : en pleine execution de l'orchestrateur,
   WinSCP et toute nouvelle session PuTTY ont commence a echouer
   ("Le serveur a fermé la connexion de manière inattendue"), alors que
   `sshd` tournait normalement (`systemctl status sshd` actif, port 22
   en ecoute). Cause reelle trouvee dans les logs `sshd` :
   `Couldn't open /dev/null: Permission denied` sur chaque nouvelle
   connexion. `ls -la /dev/null` a revele que `/dev/null` n'etait plus
   le peripherique caractere du noyau mais un FICHIER ORDINAIRE de 14
   octets (`-rw-r--r--` au lieu de `crw-rw-rw-`) - SELinux (Enforcing)
   refusait, a raison, qu'un processus traite ce fichier comme le
   device null. Ni firewalld (active par `ES_011.sh`, piste explorée et
   écartée) ni aucun job du projet ne touchent `/dev/null` (verifie sur
   tout `jobs/*.sh` - uniquement des redirections `> /dev/null`
   classiques, qui ne recreent jamais le device tant qu'il existe deja).
   Hypothese retenue (non certaine) : `ES_001` effectue une mise a jour
   OS (`dnf update`) tot dans le pipeline - une mise a jour
   systemd/udev en cours de session peut, rarement, laisser une
   fenetre ou `devtmpfs` n'a pas encore reattache `/dev`, pendant
   laquelle un `> /dev/null` execute par n'importe quel processus du
   systeme cree un fichier normal a la place. Reparation (a la main,
   sur la VM, aucun code du projet a corriger) :
   `rm -f /dev/null && mknod -m 666 /dev/null c 1 3 && chown root:root
   /dev/null && restorecon -v /dev/null` (`setenforce 0` avait
   temporairement contourne le refus SELinux pour confirmer le
   diagnostic, mais n'est pas la reparation - `setenforce 1` remis
   ensuite).

8. **Correctifs de fond suite aux incidents 6 et 7 ci-dessus** (2026-08-14,
   meme journee) : demande explicite - passer les 261 jobs en revue pour
   eviter tout blocage similaire lie a l'activation/desactivation/mauvaise
   configuration d'un service ou parametre systeme, et rendre l'archive
   elle-meme robuste (pas seulement le correctif manuel applique en
   direct sur VM1). Trois ajouts :
   - `check_dev_null()` (`lib/commun.sh`) : verifie avant CHAQUE job que
     `/dev/null` est bien un peripherique caractere, et le repare
     automatiquement si non (meme sequence que la reparation manuelle de
     l'incident 7). Appelee par `orchestrator.sh` avant chaque job.
   - `ES_011.sh` : ajout d'une verification post-application - relit
     `firewall-cmd --list-services` apres l'ajout de la regle SSH et
     echoue bruyamment si `ssh` n'y apparait pas reellement, au lieu de
     supposer que la commande a fonctionne (motive par un cas reel vecu
     le meme jour : une commande `--add-service=ssh` executee a la main
     avait echoue silencieusement, daemon pas encore demarre).
   - `WAZ_018_NET.sh` : audit systemique des 261 jobs - un seul autre
     risque reel de meme nature identifie (coupure reseau sortante
     totale en attente de `WAZ_021_RECOVER.sh`, meme categorie de risque
     "verrouillage si la chaine s'interrompt" que l'incident firewalld).
     Ajout d'un filet de securite (dead man's switch) : un processus
     detache leve automatiquement la coupure apres
     `WAZ_NET_TEST_TIMEOUT_SEC` (300s par defaut) meme si
     `WAZ_021_RECOVER.sh` ne s'execute jamais. Aucun autre job du projet
     ne touche `sshd_config`/PAM/SELinux/NetworkManager/udev/modules
     noyau.

9. **Mot de passe `elastic` desynchronise du cluster (`401` sur ES_028)**
   (2026-08-14, pre-demo, VM1) : `ES_028` (pipeline d'ingestion JSON)
   echouait avec `security_exception: unable to authenticate user
   [elastic]`, HTTP 401 - alors qu'`ES_022` (armement du mot de passe),
   `ES_026` (demarrage) et `ES_027` (controle de sante) etaient tous
   passes `OK` juste avant. Cause : `bootstrap.password` (keystore) n'est
   lu par Elasticsearch qu'a la toute premiere creation de l'index de
   securite - inoperant si le dossier de donnees a survecu d'une
   tentative de deploiement anterieure sur la meme machine (vecu en reel
   ce jour-la, plusieurs installations/echecs successifs sur VM1). Le mot
   de passe reellement actif dans le cluster restait donc celui d'un tout
   premier bootstrap anterieur, different de celui ecrit dans
   `state/es_bootstrap_password.secret` par cette execution. Angle mort
   supplementaire identifie : `ES_027` utilisait `curl` sans `-f` ni
   authentification - un `401` compte comme une reponse "reussie" pour
   curl dans ce mode, donc ce controle ne prouvait que "le port repond",
   jamais "l'authentification fonctionne". Deblocage immediat effectue a
   la main sur VM1 (`elasticsearch-reset-password` + resynchronisation du
   fichier), puis corrige dans le code source (voir section
   "Reinitialisation du mot de passe `elastic`" ci-dessous) pour que ce
   genre de desynchronisation soit detecte et repare automatiquement,
   sans jamais exiger de commandes tapees a la main sur une machine
   client.

## Reinitialisation du mot de passe `elastic` (`reinitialiser_mdp_elastic.sh`)

Ajoute le 2026-08-14 suite a l'incident 9 ci-dessus. Avant ce script, la
reparation d'un mot de passe `elastic` desynchronise exigeait une
sequence de commandes tapees a la main (`elasticsearch-reset-password`,
puis recopier la valeur au bon endroit, avec les bons droits) - source
d'erreur reelle et rien de reproductible a documenter pour un client.
Desormais :

- **Un seul point d'entree sanctionne** : `./reinitialiser_mdp_elastic.sh`
  (ou `wpwreset` via `operator_profile.sh`). Aucune autre procedure ne
  doit etre utilisee pour toucher ce mot de passe.
- **Une seule reference** : `state/es_bootstrap_password.secret` reste LA
  valeur canonique - le script l'ecrase avec la nouvelle valeur et
  personne d'autre n'a besoin d'etre mis a jour a la main. Tout ce qui
  consomme ce mot de passe (`es_admin_curl`, `escreds` dans
  `operator_profile.sh`) le relit directement depuis ce fichier a chaque
  usage, jamais une copie mise en cache ailleurs.
- **Verification systematique** : le script ne se contente jamais de
  supposer que la reinitialisation a fonctionne - il fait immediatement
  un appel authentifie reel (`_cluster/health`) avec la valeur qu'il
  vient d'ecrire, et echoue bruyamment si ce n'est pas un `HTTP 200`.
- **Auto-guerison, pas seulement un outil manuel** : `jobs/lib/es_admin_curl.sh`
  (utilise par tous les jobs `ES_02x`+ qui appellent l'API en tant
  qu'administrateur) verifie desormais l'authentification avant chaque
  appel et invoque automatiquement ce script des qu'un `401` est detecte,
  puis reessaie une fois - sans intervention humaine dans le cas courant.
  `ES_027` fait de meme immediatement apres le demarrage du service, pour
  detecter et reparer une desynchronisation le plus tot possible dans la
  chaine plutot que plusieurs jobs plus loin sur une erreur qui semble
  sans rapport.

10. **`ES_046` bloque par sa propre securite (`index_not_found_exception`,
    "forbids automatic creation")** (2026-08-14, pre-demo, VM1, juste
    apres l'incident 9) : `ES_046` (test de charge d'ingestion) ecrivait
    dans un index nomme `factory-stresstest`. Or `ES_041`, deux jobs plus
    haut dans la meme chaine, restreint la creation automatique d'index a
    `log-*,wazuh-*` uniquement (`action.auto_create_index`) - une mesure
    de durcissement deliberee pour empecher toute creation d'index hors
    gabarit. `factory-stresstest` ne correspondant a aucun des deux
    motifs, sa creation etait refusee par le cluster lui-meme,
    exactement comme concu... sauf que ce cas d'usage interne n'avait
    jamais ete rejoue bout en bout avant ce jour (deux jobs ecrits
    independamment, jamais confrontes ensemble). Corrige : index renomme
    `log-factory-stresstest` (motif deja autorise) - au passage, le test
    exerce desormais le vrai gabarit de production (`ES_040`) au lieu
    d'un nom ad-hoc non templatise, ce qui le rend plus representatif
    qu'avant, pas juste reparee.

11. **Fichiers de travail des jobs eparpilles dans `/tmp` systeme**
    (2026-08-14, signale par l'operateur en observant `/tmp` avant une
    execution) : ~28 jobs (`ES_028` a `WAZ_022`, la plupart des jobs
    Elasticsearch/Kibana/Filebeat/Logstash qui verifient une reponse API
    via un fichier temporaire) ecrivaient directement dans `/tmp/<nom>.json`,
    le `/tmp` partage par toute la machine, pas un dossier propre au
    projet. Ce n'etait pas un bug de fonctionnement - chaque fichier est
    bien supprime automatiquement si le job reussit - mais un job qui
    echoue laisse volontairement le sien pour preuve (ex. `es046.json`
    lors de l'incident 10 ci-dessus), et ces traces s'accumulent au fil
    des echecs reels, au milieu des fichiers d'autres processus de la VM.
    Corrige sur le meme principe que `STATE_DIR`/`LOG_DIR` : nouvelle
    variable `WORK_TMP_DIR` (`state/tmp/`) dans `vars.conf`, creee par
    `orchestrator.sh` et `forcer_job.sh`, et les 28 jobs concernes y
    ecrivent desormais au lieu du `/tmp` systeme - une seule reference,
    rangee dans le projet, jamais dispersee sur la machine hote.

12. **`ES_052` declare Elasticsearch reparti sans jamais le verifier
    (race condition post-crash-test)** (2026-08-14, pre-demo, VM1) :
    `ES_051` tue Elasticsearch avec `pkill -9` (crash-test volontaire),
    puis `ES_052` enchainait immediatement `systemctl start
    elasticsearch` et se declarait OK des que la commande rendait la
    main. Observe en reel : `journalctl -u elasticsearch` ne montrait
    AUCUNE nouvelle ligne "Starting Elasticsearch..." apres le crash -
    le `systemctl start` d'ES_052, lance dans la meme seconde que le
    `pkill -9`, est arrive pendant que systemd n'avait pas encore fini
    de constater la mort du processus (transition vers l'etat "failed"
    pas instantanee) ; sur une unite que systemd croit encore active,
    `systemctl start` ne fait rien et rend quand meme un code de sortie
    0. Consequence : Elasticsearch est reste `failed` pendant 8+
    minutes sans qu'aucun job ne le detecte, et `ES_053` (poll de
    sante, 5 min max) a tourne a vide avant d'echouer sans aucun indice
    sur la vraie cause. Meme famille de bug que ES_027/le mot de passe
    `elastic` (l'incident 9 plus haut) : un job ne doit jamais assumer
    qu'une action a fonctionne. Corrige : `ES_052` attend 2s avant sa
    premiere lecture d'etat (supprime la fenetre de course a la
    racine), puis reinterroge l'etat reel via `systemctl is-active` en
    boucle (jusqu'a 2 minutes), ne retente `systemctl start` que si
    l'unite est effectivement en echec (pas simplement "encore en train
    de demarrer"), et echoue explicitement avec le statut systemd
    complet si Elasticsearch n'est toujours pas actif au bout du
    delai. Teste avec un `systemctl` factice reproduisant le
    redemarrage normal (failed -> activating -> active) et le cas d'un
    service qui ne repart jamais (echec explicite avec cause visible).

13. **Audit systemique post-incident 12 - 5 autres jobs avec le meme
    risque** (2026-08-14, meme session, demande explicite de
    l'operateur : "parcourez tous les jobs qui auront les memes
    problemes et corrigez, anticipez") : recherche de tout job appelant
    `systemctl start/restart/stop/reload` dans toute la suite (`grep`
    sur `jobs/*.sh`). Sur 9 jobs trouves, 3 etaient deja surs (`ES_026`
    verifie deja le code de retour et affiche `journalctl` sur echec ;
    `WAG_005` verifie deja `systemctl is-active` apres coup ;
    `WAZ_017E_AUTHAPPLY` avertit deja explicitement en cas d'echec, sans
    jamais masquer un probleme - limite connue et documentee). Les 5
    autres avaient exactement le meme point aveugle qu'ES_052 (aucune
    verification reelle apres l'action) :
    - `ES_055` (redemarrage a froid complet) - ne lisait meme pas le
      code de sortie de `systemctl restart`.
    - `KB_024` (relance Kibana apres un test de cablage reseau) - meme
      lacune ; `KB_025` juste apres (export des Saved Objects) aurait pu
      echouer silencieusement contre un Kibana pas encore pret, sans
      jamais verifier le code de sortie de `curl` ni le contenu du
      fichier obtenu.
    - `WAZ_028` (redemarrage de `wazuh-manager` apres le crash-test
      `WAZ_027`) - **le plus expose des 5** : meme risque de course
      qu'ES_052 (un `pkill -9` juste avant, dans la meme chaine), et
      aucun job en aval (`WAZ_029` fait de la rotation de logs, pas un
      controle de sante) ne verifiait quoi que ce soit.
    - `WAZ_035_MODE_CONVERGENT` (bascule vers Kibana) - le controle en
      aval (`WAZ_037_CONVERGENT_TEST`) n'est qu'un avertissement non
      bloquant par conception (delai d'indexation possible), donc un
      manager qui ne redemarre pas aurait pu passer inapercu.
    - `WAZ_039_MODE_SOUVERAIN` (retour a la dalle native) - **le plus
      subtil** : le controle en aval (`WAZ_040_KIBANA_SILENT`) verifie
      uniquement l'ABSENCE d'evenement cote Logstash/Kibana - un
      `wazuh-manager` qui ne redemarre pas est lui aussi silencieux, et
      aurait ete pris a tort pour une preuve de bascule reussie
      ("mode souverain etanche").
    Corrige sur le meme principe que les secrets/le mot de passe
    `elastic`/`WORK_TMP_DIR` plus haut : plutot que 6 copies quasi-
    identiques de la meme boucle de verification (qui auraient fini par
    diverger), une seule fonction partagee `wait_for_service_active()`
    ajoutee a `lib/commun.sh`, appelee par `ES_052`, `ES_055`, `KB_024`,
    `WAZ_028`, `WAZ_035_MODE_CONVERGENT` et `WAZ_039_MODE_SOUVERAIN`.
    `ES_053` et `ES_056` (polls de sante deja bornes dans le temps)
    recoivent en plus un dump du statut systemd en cas de timeout,
    pour ne plus jamais laisser un operateur devant un simple
    "timeout" sans piste (c'est precisement ce qui avait rendu
    l'incident 12 difficile a diagnostiquer en reel). Teste : la
    fonction partagee, appelee directement depuis `lib/commun.sh` avec
    un `systemctl` factice, reproduit correctement le redemarrage
    normal et l'echec permanent (avec diagnostic) ; `KB_025` verifie de
    la meme facon la detection d'un export vide et d'une reponse
    d'erreur Kibana.

14. **`ES_061` interroge `_cluster/health` SANS authentification**
    (2026-08-14, pre-demo, VM1, premiere fois que l'orchestrateur
    atteignait ce point de la chaine) : `curl` sans `-u`, alors que la
    securite Elasticsearch est active depuis `ES_022`/`ES_027`. Toute
    requete non authentifiee recoit un `401` (`security_exception`),
    dont le corps ne contient evidemment jamais `"status":"green"` ou
    `"yellow"`. Le job echouait donc systematiquement avec le message
    trompeur "cluster non sain, signal NON emis", alors que le cluster
    etait en realite parfaitement sain (confirme par `ES_053` a `ES_060`
    juste avant, tous `OK` dans la meme execution). Seul job de tout le
    projet a interroger l'API Elasticsearch directement sans passer par
    `es_admin_curl` - audit des 7 autres jobs touchant l'API ES : tous
    deja authentifies (`WAZ_020_VERIFY`) ou de simples tests de liveness/
    poignee de main TLS qui n'ont pas besoin de lire le corps de la
    reponse (`ES_045`, `ES_053`, `ES_056`, `ES_050`/`ES_050B` qui
    creent l'authentification elle-meme et ne peuvent donc pas encore
    s'en servir, `LS_024` qui ne fait que generer un fichier de
    configuration). Corrige : `ES_061` passe desormais par
    `es_admin_curl` comme tous les autres controles admin du projet
    (`ES_046`, `WAZ_037`, `WAZ_040`...). En prime, le fichier de
    diagnostic n'est plus supprime en cas d'echec - il l'etait avant,
    seule exception a la convention du reste du projet (voir incident
    11 : un job qui echoue doit laisser sa preuve). Teste : `es_admin_curl`
    appele directement avec un `curl` factice authentifie confirme
    renvoyer `"status":"green"` correctement exploitable par le `grep`
    du job.

15. **`ES_050B` traite un succes reel comme un echec (`"created":false`)**
    (2026-08-14, pre-demo, VM1, juste apres l'incident 14) : POST
    `_security/user/<nom>` a une semantique UPSERT cote Elasticsearch -
    si l'utilisateur `factory_ingest_user` existe deja (`state/`
    reinitialise mais le cluster, lui, a survecu depuis un run
    precedent - meme situation racine que l'incident 9), l'appel REUSSIT
    et met a jour le mot de passe vers la nouvelle valeur generee, mais
    la reponse contient `"created":false` (pas `true`) pour signaler
    qu'il ne s'agissait pas d'une creation. Le job ne verifiait que
    `"created":true` et traitait a tort ce succes reel comme un echec -
    confirme en reel : `{"created":false}` dans le fichier de
    diagnostic, alors que le mot de passe avait bel et bien ete mis a
    jour cote cluster. Seul job de tout le projet a appeler
    `_security/user/<nom>` (verifie par recherche sur `jobs/*.sh`) -
    `ES_050` (son equivalent cle API) n'a pas ce risque : `_security/
    api_key` cree toujours une nouvelle cle, pas de semantique upsert.
    Corrige : le code HTTP redevient la seule source de verite (`200` =
    l'appel a reussi, cree OU mis a jour) - `"created"` n'est plus
    qu'informatif dans le message affiche a l'operateur. Teste avec un
    `curl` factice : `created:false` + HTTP 200 confirme desormais
    reussir (mot de passe bien ecrit dans le fichier secret), un vrai
    401 continue d'echouer correctement.

16. **Regression introduite par le correctif de l'incident 12 : mauvais
    chemin de sourcing pour `lib/commun.sh`** (2026-08-14, pre-demo, VM1,
    detecte des le premier relancement avec `SKIP_JOBS` actif) : `ES_052`
    a echoue immediatement avec `jobs/lib/commun.sh: Aucun fichier ou
    dossier de ce type` puis `wait_for_service_active: commande
    introuvable`. Cause racine : `lib/commun.sh` vit a la racine du
    projet (`wazuh_factory_3/lib/`), PAS dans `jobs/lib/` (qui ne
    contient que `es_admin_curl.sh`/`es_auth.sh`, propres aux jobs
    `ES_0xx`). Les 6 jobs corriges lors de l'audit de l'incident 13
    (`ES_052`, `ES_055`, `KB_024`, `WAZ_028`,
    `WAZ_035_MODE_CONVERGENT`, `WAZ_039_MODE_SOUVERAIN`) sourcaient
    `lib/commun.sh` avec `"$(dirname "${BASH_SOURCE[0]}")/lib/commun.sh"`
    - pattern copie par erreur depuis les jobs qui sourcent
    `es_admin_curl.sh` de la meme facon (correct pour EUX seulement, car
    ce fichier est reellement dans `jobs/lib/`). Ces 6 jobs plantaient
    des leur toute premiere ligne de source - invisible a `bash -n` (la
    syntaxe est valide, seul le chemin au runtime est faux) et non
    detecte par les tests fonctionnels precedents (executes en pointant
    `lib/commun.sh` a la main, sans reproduire le vrai layout `jobs/` vs
    racine). Corrige en reprenant le pattern deja utilise correctement
    ailleurs dans le projet (`KB_014.sh`, `LS_020.sh`, `LS_024.sh`) :
    `PROJECT_ROOT="$(dirname "$VARS_FILE")"` puis
    `source "$PROJECT_ROOT/lib/commun.sh"` - robuste quel que soit le
    sous-dossier du job, car `VARS_FILE` est toujours exporte vers la
    racine du projet par `orchestrator.sh`/`forcer_job.sh`. Verifie :
    grep exhaustif confirmant plus aucune occurrence du mauvais pattern
    dans `jobs/*.sh`, `bash -n` propre sur les 6 fichiers, test
    fonctionnel REEL (pas mocke) executant `ES_052.sh` avec un vrai
    `lib/commun.sh` copie au bon endroit relatif et un `systemctl`
    factice - confirme le sourcing puis `wait_for_service_active`
    fonctionnels de bout en bout.

17. **`LS_B025_ARMED` (et 9 autres jobs keystore) se declarent OK sans
    verifier que l'ecriture a reellement eu lieu** (2026-08-14, pre-demo,
    VM1, juste apres que le bloc Elasticsearch complet ait enfin tourne
    sans accroc) : la chaine Logstash a bloque des `LS_027`, qui a
    signale un timeout ("pipeline non demarre"). `journalctl -u logstash`
    a montre Logstash en boucle de redemarrage (13+ tentatives) avec
    l'erreur `Cannot evaluate ${FACTORY_INGEST_TOKEN}. Replacement
    variable ... is not defined in a Logstash secret store` - alors que
    `LS_B025_ARMED` (le job cense armer ce token dans le keystore juste
    avant) s'etait declare `OK`. Diagnostic confirme par l'operateur :
    `/etc/logstash/logstash.keystore` n'existait meme pas sur le disque.
    Meme famille de bug que `ES_052` avant son propre correctif (incident
    12) : `logstash-keystore create`/`add ... --stdin --force` n'etaient
    jamais verifies - le job faisait `echo OK; exit 0` inconditionnellement.
    Root cause secondaire decouverte en parallele, pendant le diagnostic :
    `/dev/null` s'est retrouve transforme en fichier ordinaire (14
    octets, `644 root:root`, confirme par `ls -la`/`stat`/`ls -lZ`)
    PENDANT la boucle de crash Logstash, meme apres l'arret de
    l'orchestrateur (donc sans que `check_dev_null()` ne soit plus
    invoque). Reparation manuelle immediate en direct avec l'operateur
    (`mknod -m 666` + verification que `/dev` est bien monte en
    `devtmpfs` sans option `nodev` anormale - confirme sain). Le
    mecanisme exact de cette re-corruption (independante de `check_dev_null()`,
    qui a fonctionne correctement chaque fois qu'il a ete invoque) n'est
    pas totalement elucide, mais n'a pas d'impact sur le correctif
    principal : `check_dev_null()` continuera a detecter et reparer toute
    recurrence avant chaque job, comme concu. Corrige, avec le meme
    principe de verification post-ecriture applique systematiquement aux
    10 jobs du projet qui touchent un keystore (`LS_B025_ARMED`, `ES_021`,
    `ES_022`, `KB_017`, `KB_023`, `FB_009`, `FB_010`, `MB_009`, `MB_010`,
    `ES_062_SNAPSHOTS3REPO`) : chaque `create` verifie desormais que le
    fichier keystore existe reellement, chaque `add` verifie que la cle
    apparait bien dans `<outil> keystore list` - echec dur (`exit 1`) sur
    les 9 jobs du chemin critique, avertissement non bloquant pour
    `ES_062_SNAPSHOTS3REPO` (deja documente comme job optionnel et
    desactive par defaut). Teste fonctionnellement (pas seulement
    `bash -n`) avec un binaire `logstash-keystore` factice : ecriture
    reelle reussie confirmee `OK`, ET reproduction exacte de l'incident
    VM1 (`add` qui rend `0` sans rien ecrire) desormais confirmee `ECHEC`
    au lieu de passer inapercue.

18. **Regression introduite par le correctif de l'incident 17 : `ES_022`
    devenu bloquant pour un cas deja documente comme non bloquant**
    (2026-08-14, pre-demo, VM1, decouverte au relancement immediat) :
    `ES_022` a echoue avec `will not overwrite keystore ... because this
    incurs changing the file owner` (code de sortie `78`). Ce n'etait pas
    un nouveau bug : `ES_008` (`chown -R` vers l'utilisateur
    `elasticsearch` sur tout `/etc/elasticsearch`, rejoue a chaque
    passage) transfere la propriete d'un `elasticsearch.keystore` qui a
    survecu d'un deploiement anterieur sur ce VM (meme situation racine
    que les incidents 9 et 15) - une fois root, `elasticsearch-keystore
    add --force` refuse alors volontairement d'ecrire, protection native
    d'Elasticsearch 8.19 contre un changement de proprietaire
    involontaire. C'est exactement le scenario deja documente en tete
    d'`ES_022.sh` sous "LIMITE CONNUE" : `bootstrap.password` est de
    toute facon inoperant sur un cluster deja initialise, et
    `es_admin_curl`/`reinitialiser_mdp_elastic.sh` (incident 9) est deja
    le point sanctionne qui rattrape une desynchronisation reelle a
    l'usage - donc non bloquant pour la suite. Avant le correctif de
    l'incident 17, cet echec passait deja inapercu a chaque run sur ce VM
    (`OK` errone, mais sans consequence reelle grace au filet de securite
    en aval) ; le rendre bloquant sans discernement etait donc une
    regression, pas un progres. Corrige : `ES_022.sh` capture desormais
    le code de sortie ET la sortie texte de `elasticsearch-keystore add`,
    et distingue precisement ce cas connu (code `78` + message `changing
    the file owner` -> avertissement, on continue) de tout autre echec
    reellement inattendu (reste bloquant, jamais silencieux). Verifie en
    parallele qu'aucun des 9 autres jobs keystore de l'incident 17 n'a un
    `chown -R` equivalent sur son dossier `/etc/<service>` avant son
    propre job d'ajout (`LS_005` ne `chown` que `/var/lib/logstash` et
    `/var/log/logstash`, jamais `/etc/logstash`) - le risque est donc
    reellement isole a `ES_022`. Teste fonctionnellement (pas seulement
    `bash -n`) avec un binaire `elasticsearch-keystore` factice sur 3
    scenarios : ecriture normale reussie (`OK`), reproduction exacte de
    l'incident VM1 - keystore deja proprietaire `elasticsearch` (`OK`
    avec avertissement), echec reellement inattendu (reste `ECHEC`).

19. **`LS_B025_ARMED` incapable de reussir en execution non-interactive :
    `logstash-keystore create` bloque sur un prompt auquel personne ne
    repond** (2026-08-14, pre-demo, VM1, decouverte au relancement
    immediat apres l'incident 18) : le job a echoue avec `[LS_B025_ARMED]
    ERREUR : /etc/logstash/logstash.keystore n'existe toujours pas apres
    'logstash-keystore create'`. Le log detaille montrait la vraie cause :
    `logstash-keystore create` affiche `WARNING: The keystore password is
    not set. Please set the environment variable LOGSTASH_KEYSTORE_PASS.
    ... Continue without password protection on the keystore? [y/N]` et
    attend une reponse sur `stdin` via un `Scanner` Java - contrairement a
    `elasticsearch-keystore create`, `kibana-keystore create`, `filebeat
    keystore create` et `metricbeat keystore create` (aucun des 4 ne pose
    cette question, verifie sur `ES_021.sh`/`KB_017.sh`/`FB_009.sh`/
    `MB_009.sh`). Sous l'orchestrateur, rien ne repond a ce prompt : le
    `Scanner` recoit un `EOF` immediat (`java.util.Scanner.throwFor`) et
    le keystore n'est jamais cree. Ce n'est pas un faux `OK` - la
    verification d'existence ajoutee a l'incident 17 a bien intercepte
    l'echec - mais le job ne pouvait tout simplement jamais reussir en
    execution non-interactive tel qu'ecrit. `LOGSTASH_KEYSTORE_PASS`
    n'est definie nulle part dans le projet (aucun fichier `vars.conf`,
    aucun job) : le design est volontairement un keystore Logstash sans
    mot de passe, confirme par le fait qu'aucun appel `add`/`list` en
    aval ne positionne cette variable non plus. Corrige : `LS_B025_ARMED.sh`
    repond desormais explicitement `y` au prompt (`echo y |
    "$KEYSTORE_BIN" create`) au lieu de laisser l'orchestrateur se heurter
    a une question sans reponse. Audit systemique : les 4 autres appels
    `*-keystore create`/`* keystore create` du projet (`ES_021.sh`,
    `KB_017.sh`, `FB_009.sh`, `MB_009.sh`) ne presentent pas ce risque -
    leurs outils respectifs ne posent pas cette question de confirmation.
    Teste fonctionnellement (pas seulement `bash -n`) avec un binaire
    `logstash-keystore` factice reproduisant fidelement le comportement
    reel (prompt + `Scanner` qui leve une exception si aucune entree n'est
    disponible sur `stdin`) : la version d'avant correctif reproduit
    exactement l'incident VM1 (`stdin` ferme -> keystore jamais cree,
    `ECHEC`) ; la version corrigee cree bien le keystore, arme le token, et
    confirme sa presence via `logstash-keystore list` (`OK`) ; un
    deuxieme passage (keystore deja present) reste idempotent et saute la
    creation comme prevu.

## Authentification Elasticsearch (token + mot de passe, au choix)

Deux volets independants pour tout ce qui doit ecrire dans Elasticsearch
depuis l'exterieur (Logstash, Beats, scripts) :
- **ES_050** (token) -> `state/factory_ingest_apikey.secret`
- **ES_050B** (mot de passe) -> `state/factory_ingest_password.secret`

Le choix se fait via `ES_AUTH_MODE` dans `vars.conf` (`token` ou
`password`), lu par la fonction partagee `jobs/lib/es_auth.sh`. Aucun des
deux volets ne bloque l'autre : vous pouvez armer les deux et changer
d'avis a tout moment. Teste avec un serveur HTTP factice (le bon en-tete
`Authorization` part bien dans chaque mode).

`jobs_table.csv` contient les 231 jobs (dependances completes, generees
depuis le blueprint + les 2 jobs de sauvegarde). Les 231 scripts `.sh`
correspondants sont tous presents dans `jobs/`.

## Sorties Logstash (fichier / S3 / Elasticsearch, a la demande)

`LS_024` regenere entierement `/etc/logstash/conf.d/30-outputs.conf` a
chaque execution, a partir de 3 interrupteurs independants dans
`vars.conf` (les 3 peuvent etre actifs en meme temps, ce ne sont pas
des modes exclusifs comme `ES_AUTH_MODE`) :

- `LS_OUTPUT_ES_ENABLED` (true par defaut) -> vers Elasticsearch local
- `LS_OUTPUT_FILE_ENABLED` (false par defaut) -> vers un fichier texte
  local en JSON lines (`LS_OUTPUT_FILE_PATH`)
- `LS_OUTPUT_S3_ENABLED` (false par defaut) -> vers l'object storage
  OVH (S3-compatible), via le plugin `logstash-output-s3` installe a la
  volee. Necessite `OVH_S3_ENDPOINT`/`OVH_S3_REGION`/`OVH_S3_BUCKET`/
  `OVH_S3_ACCESS_KEY`/`OVH_S3_SECRET_KEY` remplis dans `vars.conf`
  (vides par defaut - aucune valeur inventee).

Le fichier de sortie est toujours **reconstruit en entier**, jamais
complete par ajout (`>>`) : changer un interrupteur puis rejouer
`LS_024` ne laisse jamais de bloc fantome d'une configuration
precedente. Verifie par un test reel (2 executions successives avec
des combinaisons differentes, contenu du fichier inspecte a chaque
fois).

## Versions des services (a renseigner avant deploiement)

Nouvelle section dans `vars.conf` : `ES_PACKAGE_VERSION`,
`LS_PACKAGE_VERSION`, `KB_PACKAGE_VERSION`, `FB_PACKAGE_VERSION`,
`MB_PACKAGE_VERSION`, `WAZ_PACKAGE_VERSION` (une seule variable pour
indexer + manager + dashboard Wazuh, comme recommande par Wazuh), plus
`ELASTIC_STACK_REPO_MAJOR` (def. `8.x`) et `WAZUH_REPO_MAJOR`
(def. `4.x`) pour la branche majeure du depot.

**Versions figees le 2026-08-11** (a la demande explicite, "prenez les
versions les plus recentes stables") : `ES_PACKAGE_VERSION` /
`LS_PACKAGE_VERSION` / `KB_PACKAGE_VERSION` / `FB_PACKAGE_VERSION` /
`MB_PACKAGE_VERSION` = `8.19.14` (dernier point-release confirme de la
branche Elastic 8.19, verifie via recherche web - Elastic est deja
passe en branche majeure 9.x, mais l'integration officielle Wazuh
publie ses templates/dashboards pour "4.x-8.x" uniquement, donc rester
sur 8.19.x est le choix compatible, pas juste "le plus recent dans
l'absolu"). `WAZ_PACKAGE_VERSION` et `WAZ_AGENT_PACKAGE_VERSION` =
`4.14.7` (derniere version stable Wazuh confirmee, juillet 2026 - la
5.0 existe en beta a cette date mais n'est pas encore stable/GA, donc
ecartee volontairement).

Champ laisse vide = derniere version du depot officiel au moment du
`dnf install`. Champ rempli (comme ci-dessus) = cette version EXACTE
demandee a `dnf`. Dans tous les cas, si le paquet est deja installe, le
job ne le change JAMAIS tout seul (juste un avertissement si ca ne
correspond pas) - a vous de desinstaller manuellement si vous voulez
changer de version sur une machine deja provisionnee. Teste reellement
(rpm/dnf simules) sur les 4 scenarios : non installe + version demandee,
deja installe version differente,
deja installe meme version, aucune version demandee.

## Dimensionnement ressources (RAM / disque / heap JVM)

Ajoute le 2026-08-11, suite a un incident reel : le disque de la VM1
(ELK_HOST, 26 Go) s'est retrouve a 100% plein pendant le premier
lancement reel, et une fois nettoye (voir onglet `MAINTENANCE_MNT` du
blueprint Excel), la RAM reelle de cette VM s'est averee etre 3,5 Go -
tres loin des 14 Go que `ES_B001_RAM_CHECK` exigeait alors EN DUR.
Avant cette date, `ES_024`/`LS_017` fixaient aussi un heap JVM de 4 Go
chacun EN DUR, sans lien avec la RAM reellement disponible.

**Tout est desormais parametrable dans `vars.conf`**, section
"DIMENSIONNEMENT RESSOURCES" (nouvelle) :

| Variable | Job qui la lit | Avant (en dur) | Valeur demo actuelle |
|---|---|---|---|
| `MIN_RAM_GB_REQUIRED` | ES_B001_RAM_CHECK | 14 | 3 |
| `ES_JVM_HEAP_SIZE` | ES_024 | 4g | 512m |
| `LS_JVM_HEAP_SIZE` | LS_017 | 4g | 384m |
| `WAZ_INDEXER_JVM_HEAP_SIZE` | WAZ_013B (nouveau job) | (non regle, choix auto OpenSearch) | 512m |
| `LS_PQ_MAX_BYTES` | LS_016 | 10gb | 2gb |
| `MIN_DISK_FREE_PCT` | ES_049 | 20 | 20 |

`vars.conf` contient, juste au-dessus de ces variables, un tableau
complet des risques par palier de RAM (1/2/3/4/8/14-16 Go) : ce qui ne
demarre pas du tout, ce qui demarre mais est fragile, et la valeur
ideale a viser des que ce projet sort du cadre demo/labo. A lire avant
de modifier ces valeurs.

**`WAZ_013B_INDXR_JVMOPTNS`** (nouveau job, entre `WAZ_013` et
`WAZ_014` dans `jobs_table.csv`) : fixe explicitement le heap JVM de
wazuh-indexer, qui auparavant demarrait avec le choix automatique
d'OpenSearch - imprevisible sur une machine a faible RAM. 238 jobs
Linux au total desormais (etait 237).

Ces valeurs demo (RESOURCE_PROFILE=DEMO_LEGER dans vars.conf) sont
adaptees au couple 3,5-4 Go RAM / ~30 Go disque de VM1 et VM2 dans
l'etat actuel du projet. VM2 (AGENT_HOST) n'a besoin d'aucun reglage -
Filebeat/Metricbeat/agent Wazuh sont des binaires legers sans JVM.
Simulation fonctionnelle rejouee apres ce changement : 185/185 jobs
ELK_HOST et 53/53 jobs AGENT_HOST, aucune dependance cassee.

### ES_001 idempotent + serveur mutualise (OS_UPDATE_MODE)

`ES_001` (mise a jour OS) etait avant inconditionnel (`dnf clean all` +
`dnf update -y` a CHAQUE execution, meme systeme deja a jour - jusqu'a
30-45 min perdues a chaque nouveau lancement de l'orchestrateur).
Corrige : verifie desormais via `dnf check-update` s'il y a vraiment
quelque chose a faire.

Ajoute egalement le meme jour : `OS_UPDATE_MODE` (vars.conf) pour le
cas ou le serveur ELK_HOST heberge AUSSI d'autres services qui ne
doivent pas etre impactes par une mise a jour systeme globale -
`full` (defaut, dnf update -y complet), `security` (uniquement les
correctifs de securite, `dnf update --security -y`), ou `skip`
(aucune mise a jour, geree hors de ce projet). Plus
`OS_UPDATE_EXCLUDE_PACKAGES` pour proteger des paquets precis (motifs
dnf, ex. `httpd,php*`) sans renoncer a mettre a jour le reste. Testes
avec un mock `dnf` sur les 4 branches (full/security/skip/valeur
inconnue) - comportement confirme correct sur chacune.

## Authentification Kibana / Wazuh Dashboard (SSO)

Ajoute le 2026-08-11. Sujet **distinct** de `ES_AUTH_MODE` (qui gere
l'authentification machine-a-machine de Logstash/Beats/scripts vers
Elasticsearch) : ici il s'agit de l'authentification **humaine**, quand
quelqu'un ouvre l'interface web Wazuh Dashboard dans son navigateur.

`KIBANA_AUTH_MODE` (vars.conf) choisit parmi 3 modes :

| Mode | Comportement | Prerequis |
|---|---|---|
| `internal` (defaut) | Compte local `WAZ_INDEXER_ADMIN_USER`/`PASSWORD`, formulaire classique | Aucun |
| `ldap` | Verification directe aupres de l'Active Directory du client (LDAP/LDAPS) - l'utilisateur tape toujours son mot de passe, mais c'est son compte AD reel | Compte de service AD (bind DN) fourni par le client |
| `saml` | Vrai SSO via AD FS - redirection, session Windows deja reconnue, **aucun formulaire** (c'est le comportement decrit a l'origine : "juste rafraichir, pas de mot de passe") | Serveur AD FS (ou Azure AD/Entra ID) deja existant chez le client |

3 jobs, isoles/optionnels comme `ES_062`/`ES_063` (n'agissent que si
leur mode est selectionne, sinon comportement neutre), inseres juste
apres `WAZ_017` (healthcheck) :

- **WAZ_017B_AUTHMODE_CHECK** : verifie que les variables necessaires
  au mode choisi sont completes, arrete clairement sinon (meme logique
  que `PKI_MODE=external`).
- **WAZ_017C_AUTHCONFIG** : regenere **en entier**, a chaque execution,
  `opensearch-security/config.yml` et `opensearch_security.auth.type`
  dans `opensearch_dashboards.yml`, a partir de la valeur ACTUELLE de
  `KIBANA_AUTH_MODE` (meme principe que `LS_024` : jamais d'accumulation,
  jamais de residu d'une execution anterieure). Fusion le 2026-08-11 de
  deux jobs distincts (`WAZ_017C_LDAPCONFIG` + `WAZ_017D_SAMLCONFIG`)
  qui n'agissaient CHACUN que dans leur propre mode : revenir de
  ldap/saml vers internal ne nettoyait alors rien, l'ancien domaine
  LDAP ou SAML restait pour toujours dans `config.yml`. Desormais,
  changer de mode = changer `KIBANA_AUTH_MODE` dans `vars.conf` puis
  rejouer l'orchestrateur, dans les deux sens, rien d'autre a nettoyer
  a la main.
- **WAZ_017E_AUTHAPPLY** : redemarre wazuh-indexer/wazuh-dashboard.

Toutes les valeurs `LDAP_*`/`SAML_*` sont **vides par defaut** dans
`vars.conf` - a remplir uniquement avec les vraies informations
fournies par l'administrateur AD/AD FS du client, jamais inventees.

**Limite assumee, pas masquee** : sur un cluster deja initialise,
appliquer reellement un nouveau domaine d'authentification necessite
`securityadmin.sh` avec un certificat client "admin" distinct du
certificat serveur genere par ce projet (PKI_003-008) - non encore
provisionne. `WAZ_017E` affiche la commande exacte en rappel manuel
plutot que de pretendre a une bascule 100% automatique qui n'aurait
pas vraiment lieu. Le compte local reste toujours actif en parallele
(`order: 0` dans `config.yml`) pour ne jamais bloquer l'acces dehors.

Syntaxe basee sur la documentation officielle du plugin de securite
OpenSearch (dont Wazuh Dashboard est derive) - a valider contre la
documentation Wazuh de la version exacte installee chez le client
avant mise en production, la syntaxe pouvant evoluer d'une version a
l'autre. Simulation fonctionnelle rejouee et verte apres la fusion :
188/188 ELK_HOST, 53/53 AGENT_HOST (241 jobs Linux au total), y compris
un aller-retour explicite ldap -> internal verifiant que le residu LDAP
disparait bien de `config.yml`.

## Bascule Convergent / Souverain (routage Wazuh -> Logstash -> Kibana)

`WAZ_035_MODE_CONVERGENT` et `WAZ_039_MODE_SOUVERAIN` sont les deux
vannes reversibles qui decident si les alertes Wazuh remontent aussi
dans Elasticsearch/Kibana (mode convergent) ou restent strictement sur
la dalle native Wazuh Indexer/Dashboard (mode souverain). Chainees
automatiquement dans `jobs_table.csv` (`WAZ_035` -> `WAZ_040`) comme
auto-test de build : le mode convergent est active, teste (injection
d'un evenement + verification dans Elasticsearch), puis desactive et
re-teste (verification de silence) - le mode souverain reste l'etat de
repos par defaut apres un run complet. Rejouables individuellement a
tout moment pour basculer manuellement en exploitation.

**Bug corrige le 2026-08-12** : la version d'origine togglait un
`<enabled>`/`<disabled>` global dans `ossec.conf` via un `sed` relatif
(assume l'etat precedent, l'inverse), sans jamais cibler le bloc
`<syslog_output>` reellement responsable du forward vers Logstash
(ajoute par `WAZ_023`, sans balise de controle a l'origine). Consequence
reelle : couper le mode souverain ne coupait pas le forward, il restait
actif en continu - a l'oppose de ce que `WAZ_040_KIBANA_SILENT` est
cense verifier juste apres. Corrige, meme principe que
`WAZ_017C_AUTHCONFIG` : le bloc porte desormais un marqueur explicite
(`<!-- WEF_LOGSTASH_FORWARD -->`), et `WAZ_035`/`WAZ_039` forcent sa
valeur `<disabled>` a l'etat cible exact (no/yes) au lieu de deviner -
idempotent, verifie par rejeu multiple et aller-retour convergent ->
souverain -> convergent sur un `ossec.conf` de test contenant des
balises `<enabled>`/`<disabled>` decoy sans rapport (non affectees).

## Sauvegarde des index Elasticsearch vers S3 OVH (optionnel)

Deux jobs ajoutes hors blueprint, prepares "au cas ou" mais desactives
par defaut (`ES_SNAPSHOT_S3_ENABLED=false`) :

- **ES_062_SNAPSHOTS3REPO** : installe le plugin `repository-s3`, arme
  les identifiants OVH dans le keystore Elasticsearch, enregistre le
  depot de snapshots.
- **ES_063_SNAPSHOTPOLICY** : cree la politique SLM (planification +
  retention en jours, `ES_SNAPSHOT_RETENTION_DAYS`) qui declenche les
  sauvegardes automatiquement.

Isoles comme `INFRA_001`/`INFRA_002` : rien d'autre ne depend d'eux. Si
desactives ou mal configures, ils ne font rien et sortent en succes -
ne bloquent jamais la chaine.

## Point d'attention specifique a la bascule single-host -> 2 VM

Le blueprint d'origine assumait un seul hote (tout en 127.0.0.1). Les
jobs suivants devront explicitement utiliser `${FACTORY_HOST_IP}` /
`${BEATS_HOST_IP}` au lieu de la boucle locale quand ils seront ecrits :

- **PKI_007** (deja fait) : SAN du certificat serveur inclut desormais
  `${FACTORY_HOST_IP}` en plus de 127.0.0.1, sinon Filebeat/Metricbeat
  distants rejetteront le certificat TLS de Logstash.
- **LS_007/LS_008/LS_009** (pare-feu Logstash) : ouvrir les ports
  514/5044 a `${BEATS_HOST_IP}` (ou au sous-reseau), pas seulement en
  local.
- **LS_020** (entree Logstash) : actuellement prevu pour ecouter sur
  127.0.0.1 uniquement - doit ecouter sur `0.0.0.0` ou l'IP de VM1 pour
  accepter les connexions entrantes de VM2.
- **FB_012 / MB_012** (sortie Filebeat/Metricbeat) : actuellement prevu
  vers `https://127.0.0.1:5044` - doit pointer vers
  `https://${FACTORY_HOST_IP}:5044`.

## Reprise de deploiement / maintenance (scripts, pas juste un tableau)

Ajoute le 2026-08-12. Le blueprint documentait deja la procedure de
maintenance (onglet `MAINTENANCE_MNT`, MNT_001-020, `ON_DEMAND (Human)`
= commandes a taper a la main) mais rien ne l'executait vraiment.
Desormais, sur chaque machine, en plus de `./orchestrator.sh` :

- **`./reprise_deploiement.sh`** (a lancer AVANT `orchestrator.sh`, en
  cas de doute) : lecture seule, dit exactement quoi faire selon l'etat
  reel de la machine - premier lancement, reprise apres un arret,
  besoin de forcer la reapplication d'un nouveau heap JVM (les jobs
  deja marques `.ok` ne se rejouent pas tout seuls meme si vars.conf a
  change depuis), ou machine "louche" (paquets deja presents sans etat
  orchestrateur - purge complete recommandee avant de continuer).
- **`maintenance/MNT_diagnostic.sh`** : rejoue MNT_001-005 (df/du en
  cascade jusqu'a `/var/ossec/queue`) - lecture seule.
- **`maintenance/MNT_purge_rapide_disque.sh`** : rejoue MNT_006-009 -
  vide le cache CVE du Vulnerability Detector (rechargeable, sans
  risque, cause reelle d'un incident disque plein deja rencontre sur ce
  projet).
- **`maintenance/MNT_purge_complete_reinstall.sh`** : rejoue MNT_010-018
  - desinstallation totale d'une ancienne stack ELK/Wazuh, confirmation
  demandee avant toute suppression (destructif).

## Historique complet des executions (pas seulement la derniere)

Ajoute le 2026-08-12. Avant, un fichier `state/<COND>.ok` ne gardait que
la date de la DERNIERE reussite d'un job - ecrase a chaque
re-execution, aucune trace des tentatives precedentes (utile en plein
depannage, comme sur cette VM aujourd'hui, ou un meme job peut tourner
plusieurs fois dans la journee).

Desormais, CHAQUE execution reelle d'un job (pas les jobs sautes car
deja `.ok`) laisse deux traces :
- une ligne, jamais reecrite, dans `state/JOBS_HISTORY.csv`
  (`TIMESTAMP,JOB_ID,JOB_NAME,RESULT,LOG_FILE`) ;
- un fichier de log DEDIE a cette execution precise, dans
  `state/history/<JOB_ID>/<timestamp>.log` - la sortie exacte de CE
  run-la, rien d'autre.

Pour consulter, `./historique_job.sh` a la racine :
```
./historique_job.sh                    # liste les jobs ayant un historique
./historique_job.sh ES_017              # liste toutes les executions de ES_017
./historique_job.sh ES_017 3            # affiche le log de la 3e execution
./historique_job.sh ES_017 20260812     # affiche le log dont le timestamp contient ce texte
```
Teste : un meme job execute 2 fois dans la meme minute (echec puis
succes) produit bien 2 lignes distinctes dans le registre et 2 fichiers
de log distincts, chacun consultable individuellement.

### Statistiques par job (audit de frequence) et rapport global

`./historique_job.sh <JOB_ID> stats` calcule, a partir du registre :
nombre d'executions, taux de reussite, intervalle entre chaque
execution successive (moyenne/min/max). Avec un 3e argument en
secondes (`./historique_job.sh <JOB_ID> stats 300` pour un cycle
attendu de 5 minutes), chaque intervalle est compare a la frequence
attendue (tolerance +/-20%) et les ecarts sont signales explicitement -
utile pour verifier qu'un job cense tourner regulierement le fait
vraiment, pas juste esperer que c'est le cas.

`./rapport_audit.sh` donne la vue d'ensemble (tous les jobs ayant un
historique, executions/OK/ECHEC/dernier statut) - `--echecs` filtre sur
les jobs ayant eu au moins un echec.

Teste avec un job cyclique simule (5 executions espacees de 5 minutes,
avec un ecart volontaire de 7 minutes sur l'une d'elles) : l'ecart est
bien detecte et signale, et - point verifie explicitement - consulter
le log d'une seule execution (`./historique_job.sh JOB 3`) ne renvoie
QUE le contenu de cette execution precise, jamais melange avec les
autres (contrairement a des systemes qui empilent 30 jours de sortie
dans un seul fichier).

### Retention / expiration de l'historique (SYSOUT)

Ajoute le 2026-08-12. Sur un vrai systeme mainframe/JCL, une SYSOUT
n'est pas conservee indefiniment dans le spool - elle finit par
expirer. Ici pareil : `HISTORY_RETENTION_DAYS` dans `vars.conf` (7
jours par defaut, adapte au contexte demo - a remonter en production
selon la politique d'audit/conformite du client) fixe la duree de
conservation de chaque ligne du registre ET de son fichier de log,
**ensemble** - jamais une ligne de registre qui pointe vers un log deja
supprime, jamais un fichier de log orphelin sans ligne de registre.

`maintenance/MNT_purge_historique.sh` applique cette regle : il tourne
automatiquement, silencieusement, au tout debut de chaque
`./orchestrator.sh` (avant le premier job), et reste aussi lancable
seul a tout moment. Il ne bloque jamais le demarrage meme s'il echoue.

Teste : registre seede avec une execution vieille de 11 jours (ligne +
fichier de log) et une execution vieille d'1 jour, retention fixee a 7
jours - apres purge, la ligne et le log de plus de 7 jours ont bien
disparu ensemble, la ligne et le log recents sont bien conserves,
l'entete du registre est preservee, et le sous-dossier
`state/history/<JOB_ID>/` devenu vide a ete nettoye.

## Etat vivant (EN_COURS) - savoir "il en est ou MAINTENANT"

Ajoute le 2026-08-12. Tout ce qui precede (historique, stats, audit) ne
renseigne que sur des executions DEJA TERMINEES. Aucun moyen jusque-la
de savoir, depuis un autre terminal pendant qu'`./orchestrator.sh`
tourne, "il en est ou la maintenant" - equivalent du statut
EXECUTING/ACTIVE chez Control-M, Autosys ou le JES d'un mainframe IBM.

Desormais, un marqueur `state/RUNNING/<JOB_ID>.running` (PID reel +
horodatage) existe UNIQUEMENT pendant que ce job tourne reellement, et
un marqueur `state/RUNNING/_ORCHESTRATEUR.running` existe pendant toute
la duree de vie de l'orchestrateur - tous deux disparaissent des la fin
(succes, echec, ou interruption propre type Ctrl+C, via un trap).

Consultation, depuis un autre terminal :
```
./statut_live.sh
```

Point de rigueur (ISTJ) : la seule PRESENCE d'un marqueur n'est jamais
prise pour argent comptant - `statut_live.sh` verifie systematiquement
que le PID qu'il contient repond encore (`kill -0`). Si le PID ne
repond plus, le marqueur est annonce explicitement comme PERIME
(execution interrompue brutalement - crash, `kill -9`, coupure - sans
passage par le trap de nettoyage), jamais comme "en cours". Teste dans
les 3 cas : process reellement vivant (EN COURS correctement annonce),
process tue (PERIME correctement detecte), et un vrai `kill -9` sur
l'orchestrateur en pleine execution (le SIGKILL empeche le trap de
s'executer, laissant volontairement un marqueur perime - `statut_live.sh`
le detecte et le signale sans se tromper).

## Jobs EN ATTENTE et Force Start (equivalent Control-M/Autosys/JES)

Ajoute le 2026-08-12. `statut_live.sh` liste aussi, sous "Jobs EN
ATTENTE", tous les jobs du ROLE courant pas encore `.ok` dont au moins
une dependance (IN_COND) n'est pas satisfaite - equivalent du statut
WAITING/HELD chez Control-M/Autosys/JES, avec la dependance manquante
affichee explicitement (pas juste "en attente", mais "en attente DE
QUOI").

Pour forcer manuellement un de ces jobs a demarrer malgre la
dependance manquante (equivalent de l'action "Force Start") :
```
./forcer_job.sh <JOB_ID>
```
Toujours explicite avant d'agir : affiche la ou les dependance(s)
manquante(s), puis exige de RETAPER le JOB_ID exact pour confirmer
(pas un simple oui/non) - une mauvaise saisie annule sans rien
executer. L'execution forcee passe par EXACTEMENT le meme mecanisme
que l'orchestrateur normal (log dedie dans `state/history/<JOB_ID>/`,
marqueur EN_COURS pendant l'execution), mais est enregistree de facon
INDELEBILE et DISTINCTE dans le registre : `FORCE_OK`/`FORCE_ECHEC`,
jamais confondue avec `OK`/`ECHEC` d'une execution automatique -
`historique_job.sh <JOB_ID> stats` et `rapport_audit.sh` comptent ces
forcages dans les totaux de reussite/echec mais signalent toujours
combien d'executions etaient des forcages manuels.

Teste : job inconnu (erreur propre), job deja termine avec succes
(aucune execution, message explicite), mauvaise confirmation (annule,
rien dans le registre), et forcage reussi (script reellement execute
malgre la dependance manquante, `.ok` cree, marqueur EN_COURS nettoye,
ligne `FORCE_OK` dans le registre, bien comptabilisee par
`historique_job.sh` et `rapport_audit.sh`).

## Gel manuel (HELD) - distinct d'une simple dependance non satisfaite

Ajoute le 2026-08-12. Chez Control-M/Autosys/JES, un job WAITING se
debloque tout seul des que sa dependance est remplie ; un job HELD,
lui, reste bloque meme pret, parce qu'un OPERATEUR l'a explicitement
decide (fenetre de gel, changement en cours ailleurs). Les deux
notions etaient confondues jusqu'ici - desormais separees :
```
./geler_job.sh <JOB_ID> "<raison>"    # gele - raison obligatoire (audit)
./liberer_job.sh <JOB_ID>             # leve le gel
```
`orchestrator.sh` saute un job gele a chaque passe, meme si toutes ses
dependances sont satisfaites, SANS le marquer `.ok` ni en echec - il
reste GELE tant qu'un operateur ne le libere pas. Seuls SES
dependants restent bloques ; le reste du pipeline continue normalement
(teste : gel d'un job precoce, verification que les jobs independants
continuent de s'executer, que le job gele et tout ce qui en depend
restent non-`.ok`, puis liberation et verification qu'il s'execute
bien au run suivant).

`forcer_job.sh` refuse desormais explicitement de forcer un job gele
("un gel est une decision d'exploitation deliberee, pas contournable
par megarde par un forcage - liberez-le d'abord") - teste.

`statut_live.sh` liste les jobs GELES separement des jobs EN ATTENTE
(un job gele n'est plus compte comme "en attente de dependance" meme
s'il en a une, pour ne jamais le lister deux fois).

## Marquage manuel "deja fait" (sans execution) - distinct du gel

Ajoute le 2026-08-14, suite a une demande reelle de l'operateur sur
VM1 : geler un job (HELD) bloque tout ce qui en depend - inadapte
quand le besoin reel est "ce job est deja satisfait (ou n'a pas besoin
de l'etre), laisse le reste de la chaine continuer derriere lui" (cas
concret : sauter `ES_001`, la mise a jour OS, sans bloquer `ES_002` et
tout ce qui suit). Trois outils, trois intentions distinctes,
jamais interchangeables :
- `geler_job.sh` (HELD) : "ne joue PAS ce job, meme pret" - bloque tout
  ce qui en depend.
- `forcer_job.sh` : "joue REELLEMENT ce job maintenant, meme si ses
  dependances ne sont pas remplies".
- `marquer_deja_fait.sh` : "considere ce job comme deja reussi, SANS
  executer son script" - la chaine continue derriere.
```
./marquer_deja_fait.sh <JOB_ID> "<raison>"
```
Meme rigueur d'audit que `forcer_job.sh` : raison obligatoire,
confirmation en retapant le JOB_ID exact, refus explicite sur un job
GELE (un gel reste une decision distincte, jamais court-circuitee par
un autre outil - `liberer_job.sh` d'abord si c'est vraiment voulu), et
marquage INDELEBILE et DISTINCT dans le registre (`MARQUE_FAIT`, jamais
`OK`/`ECHEC`/`FORCE_OK`) pour qu'un audit ulterieur sache toujours
qu'aucune commande reelle n'a tourne pour ce job a ce moment precis. Le
log dedie de cette "execution" ne contient donc pas de sortie de
commande, seulement l'attestation d'audit (operateur, raison, horodatage).

Raccourci une fois `operator_profile.sh` source : `wskip <JOB_ID>
"<raison>"`.

Teste : marquage normal (marqueur `.ok` cree, trace `MARQUE_FAIT`
distincte dans l'historique), deja fait (no-op explicite), confirmation
incorrecte (annule, rien modifie), job GELE (refuse explicitement).

## Saut volontaire de jobs non bloquants (`SKIP_JOBS`) - creneau demo/test limite

Ajoute le 2026-08-14, suite a une clarification de l'operateur apres la
fonctionnalite ci-dessus : le besoin reel n'etait pas "attester qu'un
job a ete fait ailleurs" (`marquer_deja_fait.sh`), mais un scenario
different et frequent en mission client - "l'environnement de test/demo
n'est accessible que sur une fenetre courte (ex: 30 minutes), certains
jobs sont lents mais SANS IMPACT FONCTIONNEL sur la suite (ex: `ES_001`,
mise a jour OS - contrairement au demarrage d'Elasticsearch, dont tout
le reste depend reellement) - decidons A L'AVANCE de les sauter pour
tenir le creneau". Contrairement a `marquer_deja_fait.sh` (reactif,
job par job, en cours de run), `SKIP_JOBS` se decide AVANT meme de
lancer `./orchestrator.sh`, dans `vars.conf` :
```
SKIP_JOBS="ES_001"
SKIP_JOBS="ES_001,ES_046"    # plusieurs, separes par des virgules
```
Chaque job liste est saute automatiquement des que l'orchestrateur
l'atteint : son script n'est JAMAIS execute, sa condition (`OUT_COND`)
est marquee satisfaite pour que la suite de la chaine continue sans
interruption, et c'est journalise de facon indelebile et distincte
(`SAUTE_CONFIG` dans `state/JOBS_HISTORY.csv` - jamais confondu avec
`OK`/`ECHEC`/`FORCE_OK`/`MARQUE_FAIT`). Le log dedie de chaque saut
precise explicitement que rien n'a ete execute et pourquoi. Nouvelle
fonction partagee `job_in_skip_list()` dans `lib/commun.sh`, verifiee
dans `orchestrator.sh` juste apres le controle de gel (HELD) - un job
gele reste prioritaire sur `SKIP_JOBS` (les deux aboutissent au meme
resultat de toute facon : le job ne tourne pas).

Teste de bout en bout avec 3 jobs factices (A saute via `SKIP_JOBS`, B
qui depend de A, C independant) : le script de A n'est jamais execute
(verifie via un marqueur qu'il aurait du laisser s'il avait tourne), sa
condition est marquee satisfaite, B et C s'executent normalement
derriere, et la trace `SAUTE_CONFIG` apparait bien dans l'historique.

## Detection de retard (SLA) sur un job EN COURS

Ajoute le 2026-08-12, motive directement par un incident reel vecu sur
ce projet : ES_027 avait timeout apres 5 minutes sans qu'aucune alerte
n'existe PENDANT qu'il tournait - on ne l'a su qu'apres coup.

Le registre `state/JOBS_HISTORY.csv` porte desormais une 6e colonne,
DUREE_SEC (duree reelle de chaque execution, jamais estimee). Quand
`statut_live.sh` voit un job EN COURS, il calcule sa duree moyenne
historique (sur ses executions reussies passees, si au moins 2
echantillons existent) et signale explicitement "EN RETARD" si la
duree ecoulee depasse 150% de cette moyenne - sans jamais inventer un
seuil pour un job dont on n'a pas encore d'historique suffisant.

Teste : job synthetique avec un historique connu (3 executions a 2s),
lance une 4e fois deliberement plus lent (20s) - `statut_live.sh`
signale correctement "EN RETARD" apres 6s (150% de 2s = 3s), et un job
sans anomalie (deja termine) ne declenche jamais de faux positif.

## Tracabilite nominative des forcages (audit bancaire)

Ajoute le 2026-08-12. `forcer_job.sh <JOB_ID> "<raison>"` exige
desormais une raison (aucune derogation manuelle sans justification -
pratique standard en environnement bancaire/reglemente) et capture
l'identite de l'operateur (`whoami@hostname`). Les deux sont inscrites
en tete du log dedie de CETTE execution (equivalent SYSOUT) - jamais
dans le registre CSV, qui reste un simple index et pas un endroit ou
stocker du texte libre pouvant contenir des virgules.

## Alerte par email sur echec de job (notifier.sh)

Ajoute le 2026-08-12. Le plus gros manque reel face a un centre
d'exploitation 24/7 : sans ca, un job qui echoue ne fait qu'ecrire un
log - personne n'est prevenu tant qu'un humain ne va pas le lire.
`orchestrator.sh` et `forcer_job.sh` appellent desormais `notifier.sh`
automatiquement sur tout echec.

Implementation via `curl` en SMTP direct (`curl --url smtps://...`),
pas un MTA complet (postfix/sendmail) : rien a installer ni a faire
tourner comme service, coherent avec le reste du projet (scripts
autonomes plutot que daemons supplementaires).

Configuration dans `vars.conf`, section ALERTE PAR EMAIL - desactivee
par defaut (`NOTIF_ENABLED="non"`), EXPRES : aucune tentative d'envoi
tant que ce n'est pas explicitement configure. Exemple pour une
adresse hebergee chez OVH :
```
NOTIF_ENABLED="oui"
SMTP_HOST="smtp.mail.ovh.net" # port 465 SSL/TLS (verifie sur la doc OVH - Zimbra Starter)
SMTP_PORT=465
SMTP_USER="contact@ankrr.fr"
SMTP_PASS_FILE="$INSTALL_DIR/secrets/smtp_password.txt"
NOTIF_FROM="contact@ankrr.fr"
NOTIF_TO="contact@ankrr.fr"
```
**Le mot de passe n'est JAMAIS dans vars.conf** (livre dans l'archive
de deploiement) - il vit dans un fichier SEPARE (`SMTP_PASS_FILE`).
Ajoute le 2026-08-14 (demande explicite - eviter d'avoir a retaper une
commande oubliee a chaque redeploiement) : le dossier `secrets/` EST
desormais livre dans l'archive, mais volontairement VIDE (a part un
`README_SECRETS.txt` qui rappelle la marche a suivre) - vous n'avez
donc plus a le recreer, une seule commande suffit sur chaque machine :
```
echo 'le_mot_de_passe' > secrets/smtp_password.txt
chmod 600 secrets/smtp_password.txt
```
`vars.conf` pointe deja `SMTP_PASS_FILE` vers ce chemin par defaut.
Le VRAI mot de passe, lui, n'est et ne sera jamais inclus dans une
archive livree - le processus de build verifie explicitement que
`secrets/` ne contient que le placeholder avant chaque livraison.

**Compatibilite vault d'entreprise / injection par variable d'environnement**
(anticipe, non construit - le fichier `secrets/` est un choix delibere
pour ce projet, pas une contrainte architecturale). Un mecanisme de
fichier local, meme protege, n'est pas accepte par toutes les
politiques de securite (certaines DSI/banques interdisent tout mot de
passe en clair sur disque et imposent un coffre-fort centralise -
HashiCorp Vault, AWS Secrets Manager, Azure Key Vault, CyberArk - ou
une injection via variable d'environnement au demarrage du processus).
Le projet est concu pour que ce changement reste local et isole.
Preuve verifiable, pas une simple affirmation : `SMTP_PASS_FILE`
n'apparait que dans 2 fichiers de code sur tout le projet -
`vars.conf` (ou il est defini) et `notifier.sh` (ou il est lu, une
seule fois, `notifier.sh:55` : `SMTP_PASS="$(cat "$SMTP_PASS_FILE")"`)
- confirme par `grep -rn SMTP_PASS_FILE jobs/ lib/ orchestrator.sh`
(aucun resultat). Basculer vers un vault ou une variable
d'environnement se limite donc a remplacer cette seule ligne par
l'appel au coffre-fort ou une lecture de variable : aucun job, aucun
autre script du projet ne reference ni ne suppose l'existence d'un
fichier de mot de passe, donc aucune regression possible ailleurs.

Test independant de toute panne reelle : `./notifier.sh --test`.

Teste : desactive par defaut (aucune tentative), variables manquantes
(erreur claire), fichier de mot de passe absent (erreur claire),
echec reseau (erreur claire, jamais un blocage de l'orchestrateur -
verifie avec un port ferme), et envoi reussi verifie contre un serveur
SMTP local de test (le message est correctement construit et transmis
via le protocole SMTP - MAIL FROM/RCPT TO/DATA acceptes). **Verifie en
conditions reelles** avec contact@ankrr.fr (OVH) : email de test
effectivement recu dans la boite Outlook.

### Portabilite vers un autre fournisseur que OVH

Question legitime posee par l'utilisateur : ce template est-il
suffisant pour un autre fournisseur ? Reponse honnete - il y avait une
vraie limite, corrigee le 2026-08-12. `notifier.sh` forcait au depart
le mode TLS implicite (`smtps://`, adapte au port 465) quel que soit
le port configure ; un fournisseur en STARTTLS (port 587) aurait
echoue. Desormais, le mode est deduit automatiquement du port
(465 -> TLS implicite, tout le reste -> STARTTLS), ou forcable
explicitement via `SMTP_TLS_MODE="ssl"` ou `"starttls"` dans
`vars.conf` si besoin.

| Fournisseur | SMTP_HOST | SMTP_PORT | Mode | Remarque |
|---|---|---|---|---|
| OVH (Zimbra/MX Plan) | smtp.mail.ovh.net | 465 | ssl (auto) | **Verifie en reel** sur ce projet (contact@ankrr.fr) |
| Gmail / Google Workspace | smtp.gmail.com | 465 ou 587 | ssl ou starttls (auto) | Exige un "Mot de passe d'application" (16 caracteres) - le mot de passe normal du compte est refuse des que la validation en 2 etapes est active, ce qui est la norme aujourd'hui |
| Microsoft 365 / Outlook | smtp.office365.com | 587 | starttls (auto) | Beaucoup de tenants ont desactive l'authentification simple (SMTP AUTH par mot de passe) au profit de l'authentification moderne (OAuth2) - dans ce cas, un simple mot de passe ne suffit plus, il faut voir avec l'administrateur Microsoft 365 du client |
| Relais SMTP corporate/interne | (fourni par le client) | variable (25/587/465) | variable | A demander a l'equipe infrastructure du client - certains relais internes n'exigent meme aucune authentification |

Ce que ce template NE fait PAS et ne fera pas dans l'immediat : gerer
OAuth2 (obligatoire pour Gmail/Microsoft 365 des que l'authentification
moderne est imposee) - implementation nettement plus lourde
(enregistrement d'une application, jetons, rafraichissement) hors de
proportion avec ce qu'un simple script d'alerte doit faire ; si ce
blocage se presente reellement (client avec authentification moderne
forcee), il faudra le traiter specifiquement a ce moment-la plutot que
d'anticiper une solution non testee.

**Verification faite, verification pas faite (transparence) :** le
mode TLS implicite (port 465, cas OVH) est verifie de bout en bout en
conditions reelles (email recu). Le mode STARTTLS (port 587) est
implemente selon le mecanisme standard documente de curl et sa logique
de selection de port est testee unitairement, mais n'a pas ete
verifiee par un envoi reel de bout en bout dans cette session (aucun
fournisseur STARTTLS n'etait disponible pour un test reel) - a
confirmer avec un envoi `./notifier.sh --test` reel le jour ou un tel
fournisseur est configure.

## Reutilisation pour la phase EXPLOITATION (au-dela du deploiement)

Note ajoutee le 2026-08-12, suite a une question legitime de
l'utilisateur : ce projet (WAZ_ELK_FACTORY) construit et configure
l'infrastructure (Elasticsearch/Logstash/Kibana/Wazuh) - une fois
livree, la phase suivante est l'EXPLOITATION reelle, par exemple des
analyses LCB-FT (Lutte Contre le Blanchiment de Capitaux et le
Financement du Terrorisme) menees dans Kibana ou le Wazuh Dashboard.

Ce que cette discipline (historique par job, statistiques, audit
global, etat vivant EN_COURS, EN ATTENTE, gel manuel HELD, detection
de retard SLA, alerte email, tracabilite operateur) apporte
DIRECTEMENT a cette phase suivante : le moteur d'ordonnancement
(`orchestrator.sh` + `jobs_table.csv`) n'est pas specifique au
deploiement - c'est un ordonnanceur generaliste qui a d'abord servi a
installer l'infrastructure, et qui peut tout aussi bien piloter des
jobs d'EXPLOITATION recurrents (ex: une requete Kibana/Elasticsearch
d'analyse LCB-FT executee chaque jour) avec exactement les memes
garanties : historique complet de chaque execution, alerte immediate
si l'analyse echoue ou ne se termine pas dans un delai normal,
capacite de forcer/geler un cycle d'analyse avec tracabilite
nominative complete - des exigences qui comptent au moins autant en
conformite reglementaire qu'en deploiement infrastructure.

Le calendrier jours ouvres/feries, ecarte plus haut dans ce document
comme peu pertinent POUR CE projet-ci (un pipeline de deploiement
qui se joue une fois, pas un batch quotidien), redevient
legitimement pertinent POUR CETTE phase-la : une analyse LCB-FT est
typiquement un traitement quotidien qui doit respecter un calendrier
metier (jours ouvres, feries francais/europeens). Ce n'est donc pas
ecarte definitivement - simplement pas construit maintenant, dans
l'abstrait, sans jobs reels d'analyse a y accrocher (meme discipline
que le reste de ce projet : ne jamais batir un mecanisme sans cas reel
concret a servir).

Ce que ce projet n'a PAS et ne devrait PAS improviser : les regles de
detection LCB-FT elles-memes (seuils, patterns suspects, obligations
de declaration Tracfin) relevent de la conformite reglementaire et de
votre expertise metier, pas d'une extrapolation technique de ma part -
quand cette phase sera prete a etre outillee, ces regles devront venir
de vous (ou de votre service conformite), le role de l'ordonnancement
etant de les executer, tracer et surveiller de facon fiable - pas de
les definir.

## lib/commun.sh - fonctions partagees

Ajoute le 2026-08-12. `job_done()`, `mark_done()`, `component_enabled()`,
`pid_alive()` et (nouveau) `job_held()` etaient dupliquees dans
`orchestrator.sh`, `statut_live.sh` et `forcer_job.sh` - un bugfix dans
l'une exigeait de penser a le refaire dans les autres. Desormais
centralisees dans `lib/commun.sh`, source par tous les scripts
concernes (dont les nouveaux `geler_job.sh`/`liberer_job.sh`). Point
unique de correction, comportement garanti identique partout. Depuis le
2026-08-14, `lib/commun.sh` porte aussi `local_pki_copy()` (voir section
"Bugs trouves en DEPLOIEMENT REEL" plus haut).

## Vocabulaire operateur (`operator_profile.sh`)

Ajoute le 2026-08-14, a la demande de l'utilisateur qui a decrit une
pratique reelle de centre de production bancaire multi-filiales
(SGABS/Societe Generale) : un operateur ne tape jamais un chemin
complet a la main. Il connait un petit nombre de **noms courts,
toujours les memes d'un environnement a l'autre** (VM1, VM2, un futur
client...) - seule la valeur change derriere le nom, jamais le nom
lui-meme. Le cerveau retient un vocabulaire fixe, pas une variante par
machine.

**A sourcer** (jamais a executer directement) dans le shell de
l'operateur :
```
. /chemin/vers/wazuh_factory_3/operator_profile.sh
```
Pour l'avoir a chaque connexion, une seule fois :
```
echo '. /chemin/vers/wazuh_factory_3/operator_profile.sh' >> ~/.bashrc
```

Six commandes, volontairement peu nombreuses (le principe observe est
justement de ne pas surcharger la memoire) :

| Commande | Fait quoi |
|---|---|
| `wenv` | Affiche ROLE, PROJET, machine, WEF_HOME - "sur quel environnement suis-je ?" |
| `escreds` | Affiche l'URL Kibana/Elasticsearch et les identifiants de connexion (superutilisateur `elastic` + compte d'ingestion), sans avoir a se souvenir des chemins vers `state/*.secret` |
| `kburl` | Affiche l'URL Kibana |
| `wstat` | Raccourci vers `./statut_live.sh` |
| `wlog <JOB_ID>` | Raccourci vers `./historique_job.sh <JOB_ID>` |
| `wpwreset` | Raccourci vers `./reinitialiser_mdp_elastic.sh` - seul point sanctionne pour reinitialiser le mot de passe `elastic` (voir section dediee) |
| `wskip <JOB_ID> "<raison>"` | Raccourci vers `./marquer_deja_fait.sh` - marque un job deja satisfait sans l'executer, sans bloquer ce qui en depend (voir section dediee) |

**Adaptation a la nomenclature d'un client.** Un client peut deja avoir
sa propre convention de nommage pour ce type d'outillage. Tout le
vocabulaire est regroupe dans un seul bloc, clairement delimite, en bas
de `operator_profile.sh` ("VOCABULAIRE OPERATEUR") - c'est le **seul**
endroit de tout le projet a modifier pour renommer une commande (ex.
`escreds` -> `dbconn`), sans toucher a aucun autre fichier ni casser
quoi que ce soit ailleurs. S'il n'a pas de convention existante,
proposez celle-ci telle quelle en la presentant explicitement comme
**specifique a cette installation**, mise en place pour faciliter son
exploitation - pas une norme imposee.

## Structure

```
wazuh_factory_3/
├── vars.conf          <- IP des 2 VM + identifiants deja renseignes (test)
├── jobs_table.csv      241 jobs, dependances completes, verifiees par simulation reelle
├── orchestrator.sh      ordonnanceur Linux (ROLE=ELK_HOST | AGENT_HOST + AGENT_COMPONENTS)
├── jobs/                 241 scripts .sh, un par JOB_ID - suite complete
│   ├── lib/es_auth.sh          fonction es_curl() - auth externe (token/mdp)
│   ├── lib/es_admin_curl.sh    fonction es_admin_curl() - auth interne (superuser)
│   ├── PKI_001.sh ... PKI_011.sh
│   ├── INFRA_001.sh, INFRA_002.sh, DIST_001.sh
│   ├── ES_001.sh ... ES_061.sh (+ ES_B001, ES_B015, ES_050B)
│   ├── ES_062_SNAPSHOTS3REPO.sh, ES_063_SNAPSHOTPOLICY.sh   <- sauvegarde S3, optionnel
│   ├── LS_001.sh ... LS_036_FINAL.sh
│   ├── KB_001.sh ... KB_029.sh
│   ├── FB_001.sh ... FB_023.sh
│   ├── MB_001.sh ... MB_022.sh
│   ├── WAZ_001.sh ... WAZ_040_KIBANA_SILENT.sh    <- manager Wazuh, VM1 (+ WAZ_013B_INDXR_JVMOPTNS)
│   └── WAG_001.sh ... WAG_006.sh                  <- agent Wazuh Linux, AGENT_HOST
├── jobs_windows/          kit Windows separe (agent Wazuh + Filebeat + Metricbeat, PowerShell)
├── state/                fichiers .ok (crees a l'execution)
└── logs/                 journaux d'execution (un par run)
```

## 2026-09-01 - Echec reel ES_021 chez une etudiante deployant depuis GitHub

**Constat reel** : une etudiante a clone le depot public et lance
`./orchestrator.sh` sur sa propre machine (premier deploiement
independant de ce projet, jamais teste jusque-la) - `ES_021` (creation
du keystore Elasticsearch) a echoue, de facon identique et reproductible
sur deux tentatives successives (capture d'ecran transmise).

**Diagnostic, sans acces a la machine reelle (VM de reference
192.168.50.128 eteinte au moment du diagnostic)** : lecture du code
source du job + connaissance reelle du produit Elasticsearch, deux
defauts cumules identifies :

1. `elasticsearch-keystore create` s'executait en root, jamais la
   methode documentee officiellement par Elastic (`sudo -u
   elasticsearch ...`) - le proprietaire reel de `/etc/elasticsearch`
   est `elasticsearch:elasticsearch` depuis ES_008/ES_020 ; une
   incoherence entre l'utilisateur executant la commande et le
   proprietaire du dossier est une cause plausible et courante d'echec
   silencieux de ce type d'outil.
2. La sortie reelle (stdout/stderr) de la commande n'etait jamais
   capturee ni affichee en cas d'echec - impossible de confirmer la
   cause exacte sans deviner, le job se contentait de constater
   l'absence du fichier.

**Meme audit etendu a `KB_017.sh` (Kibana)** : meme motif exact
(`kibana-keystore create` en root, aucune sortie capturee) - corrige de
la meme facon par coherence, avant qu'un futur deploiement ne tombe sur
le meme probleme cote Kibana.

**Correction appliquee (ES_021.sh, KB_017.sh)** : execution desormais
comme l'utilisateur reel du service (`ES_USER`/`KB_USER`), sortie
complete capturee et affichee sur tout echec pour que le PROCHAIN
incident soit diagnosticable sans deviner.

**Honnetete sur la certitude de ce correctif** : cause la plus probable
identifiee par lecture de code et connaissance du produit, PAS
confirmee par reproduction directe (VM de reference indisponible au
moment du correctif). A verifier reellement des que possible sur une
VM Oracle Linux 8 fraiche.

**Corrige au meme moment, bug latent distinct trouve en marge** : le
correctif du 2026-09-01 sur ERP_CRM_FACTORY (partage de descripteur
stdin entre un job lance en arriere-plan et la boucle `while read` de
l'orchestrateur, code source d'origine partage entre les deux projets)
n'avait jamais ete reporte sur WAZ_ELK_FACTORY - fait maintenant, sur
`orchestrator.sh` et `forcer_job.sh`.

**Audit croise AGENT_HOST** (demande explicite du client, verifier que
FB_009.sh/MB_009.sh mentionnes dans un commentaire de LS_B025_ARMED.sh
portaient le meme defaut) : aucun des deux fichiers n'existe plus dans
ce depot (`filebeat-keystore create`/`metricbeat-keystore create`
introuvables dans jobs/ - le commentaire etait une reference obsolete a
une iteration anterieure du projet). Rien a corriger cote AGENT_HOST
pour cette classe de bug precise.

## 2026-09-03 - Boucle reelle WAZ_014A (HTTP 503 sur `_cluster/health`) sur le deploiement MIPREL (`/opt/wef`, Oracle Linux 8)

Deux incidents distincts, tous deux confirmes par preuve directe (jamais
supposes), decouverts en diagnostiquant un `WAZ_014A_INDXR_ADMINPW.sh`
qui echouait en boucle avec HTTP 503 sur `_cluster/health`.

**Incident A - `orchestrator.sh` recree lui-meme `/dev/null` avec du
contenu reel dedans.** Le rapport de fin d'execution testait l'existence
de fichiers avec `ls "$STATE_DIR"/*.ok >/dev/null 2>&1`. Si `/dev/null`
n'est plus, a cet instant precis, un peripherique caractere (bug deja
connu, voir incident 17 plus haut et `INFRA_003_DEVNULL_GUARDIAN.sh`),
la redirection `>` le RECREE comme fichier ordinaire et le vrai contenu
de `ls` (la liste des chemins `state/*.ok`) s'ecrit DEDANS au lieu
d'etre jete. Preuve directe : capture reelle de `/dev/null` corrompu
(5209 octets, `stat`/`xxd` a l'appui) contenant exactement cette liste,
caractere pour caractere. Preuve complementaire : `journalctl -u
wazuh-indexer` montrait `/dev/null: Permission non accordee` dans
`opensearch-env` ligne 92 des le demarrage du service, avant meme que
WAZ_014A ne tourne - confirmant que `/dev/null` etait deja ce fichier
`root:root` non-inscriptible a ce moment-la. **Corrige** :
`orchestrator.sh` remplace desormais ce test par un `shopt -s nullglob`
purement bash, qui ne touche jamais `/dev/null` (commit `98a7006`).

**Incident B - `internal_users.yml` vide de facon PERMANENTE dans
l'index de securite lui-meme, pas seulement dans le fichier local.**
Le log reel de `wazuh-passwords-tool.sh` (`securityadmin.sh -backup`)
montrait le cluster GREEN et bien connecte, mais `FAIL: Configuration
for 'internalusers' failed because of empty source` (et 5 autres types :
`config`, `roles`, `actiongroups`, `tenants`, `audit`) - preuve que ces
types etaient reellement vides DANS L'INDEX `.opendistro_security`, pas
juste dans le fichier. Lecture du code source de
`wazuh-passwords-tool.sh` (`/usr/share/wazuh-indexer/plugins/opensearch-
security/tools/`, paquet RPM, hors depot Git) : `passwords_createBackUp()`
ne verifie jamais l'echec individuel par type de ressource (seul le code
de sortie global de `securityadmin.sh -backup` est teste), et
`passwords_updateInternalUsers()` fait ensuite un `cp` inconditionnel du
backup (meme vide) par-dessus le vrai fichier - puis
`passwords_runSecurityAdmin()` repousse ce contenu vide DANS L'INDEX via
`securityadmin.sh -f ... -t internalusers`. Une fois qu'un premier
passage a eu lieu pendant que l'index n'etait pas encore pret (le HTTP
503 d'origine), le vide se grave ainsi de facon permanente - chaque
tentative suivante retrouve le meme vide, meme cluster GREEN, boucle
auto-entretenue. Preuve que le vide est ancien (pas cause par la
derniere tentative) : les DEUX sauvegardes horodatees dans
`/etc/wazuh-indexer/internalusers-backup/` (01h19 ET 02h42) etaient
deja a 0 octet.

**Recuperation reelle effectuee sur la VM** (`wazuh-indexer-4.14.7-1`) :
le `.rpm` d'origine etait encore en cache DNF
(`/var/cache/dnf/wazuh-*/packages/wazuh-indexer-4.14.7-1.x86_64.rpm`).
Extraction via `rpm2cpio | cpio` des 10 fichiers YAML par defaut
(`internal_users.yml` notamment : hash bcrypt public du mot de passe de
demonstration `admin`/`admin`, `_meta.type: internalusers` - format
authentique confirme par lecture), remplacement des 10 fichiers sur
disque (`chown wazuh-indexer:wazuh-indexer`, `chmod 640`), puis
`securityadmin.sh -cd /etc/wazuh-indexer/opensearch-security/` avec les
memes host/port/certificats (`localhost:9200`, `root-ca.pem`,
`admin.pem`/`admin-key.pem`) deja prouves fonctionnels par le log de
l'outil - `SUCC` confirme sur les 10 types, `Done with success`.
`./orchestrator.sh` relance ensuite : `WAZ_014A_INDXR_ADMINPW -> OK`
confirme reellement (pas suppose) via le marqueur d'etat de
l'orchestrateur.

**Corrige dans le code pour que ca ne se reproduise plus tout seul** :
`WAZ_014A_INDXR_ADMINPW.sh` detecte desormais lui-meme un
`internal_users.yml` vide AVANT d'appeler `wazuh-passwords-tool.sh`, et
applique automatiquement la meme procedure de recuperation (extraction
depuis le `.rpm` en cache DNF/YUM, `securityadmin.sh -cd`) avant de
poursuivre - un futur deploiement qui tombe dans ce piege se repare seul,
sans intervention manuelle ni acces a cette conversation.

**Honnetete sur la certitude de ce correctif** : le mecanisme de
compounding (backup vide reinjecte dans l'index) est confirme par
lecture directe du code de `wazuh-passwords-tool.sh` et par les logs
reels. La cause TOUT A FAIT initiale (pourquoi l'index etait vide pour
ces 6 types des le tout premier passage, avant meme le premier des deux
backups a 0 octet observes) n'est pas totalement elucidee - hypothese la
plus probable : un premier appel a `wazuh-passwords-tool.sh` a eu lieu
pendant une fenetre ou l'index de securite venait tout juste d'etre cree
par le demarrage initial de wazuh-indexer et n'avait pas encore ete
peuple par le bootstrap de securite embarque dans le paquet. Le
correctif d'auto-guerison rend cette question moins critique : quelle
que soit la cause initiale exacte, le symptome (fichier vide) est
desormais detecte et repare automatiquement avant de faire des degats.

## 2026-09-03 (suite) - `WAZ_020_VERIFY` echoue toujours (0 alerte) meme apres correctif WAZ_014A

Meme session, immediatement apres le correctif WAZ_014A ci-dessus :
l'orchestrateur relance avec succes jusqu'a `WAZ_019_FLOOD` (OK) puis
`WAZ_020_VERIFY` echoue (0 alerte indexee apres 6 tentatives / 30s).

**Preuve directe (pas suppose)** :
- `grep -c "wazuh-test-flood" /var/log/messages` -> **20000** (les
  messages de test sont bien arrives, intacts, au niveau syslog).
- `journalctl -t auth --since ... --until ...` -> **0** (aucun n'est
  entre dans journald).
- `grep -c "wazuh-test-flood" /var/ossec/logs/archives/archives.log` ->
  **0** (l'agent Wazuh n'en a collecte aucun).
- `ossec.conf` ne surveille que `journald` + `/var/log/audit/audit.log`
  + `/var/ossec/logs/active-responses.log` - jamais `/var/log/messages`.

**Cause reelle** : `WAZ_019_FLOOD.sh` injectait via 20000 appels
`logger -t auth` (un fork de processus par ligne - 11 minutes reelles
pour 20000 lignes, deja anormalement lent en soi). `journald` applique
une limite de debit par defaut qui absorbe silencieusement une rafale
de messages quasi-identiques en quelques secondes. Preuve que ce n'est
pas un probleme de regle de detection (contrairement au canari) : le
canari de `WAZ_041_ALERT_CANARY.sh` (1 seul message/jour, jamais
touche par cette limite) fonctionne, documente comme teste avec succes
le 2026-08-31 - la difference n'est PAS la regle, c'est le volume/debit
qui ne franchit meme pas journald.

**Corrige** : `WAZ_019_FLOOD.sh` ecrit desormais directement (bash pur,
sans fork, sans passer par journald) dans un fichier dedie
`/var/log/wazuh-flood-test.log`, ajoute comme `<localfile>` dans
`ossec.conf` par ce job lui-meme, avec sa propre regle Wazuh dediee
(id 100102, meme principe que la regle 100101 du canari) pour generer
une vraie alerte plutot que d'etre seulement archive. Beneice
secondaire : 20000 lignes ecrites en une fraction de seconde au lieu de
11 minutes (memes gains en simplicite d'execution, aucun besoin de
justifier la lenteur).

**Bug latent trouve en corrigeant celui-ci, dans un fichier partage** :
`WAZ_025.sh` faisait un `cat > local_rules.xml` INCONDITIONNEL (pas
idempotent, pas additif) - si un job numeriquement plus petit (comme
`WAZ_019_FLOOD`, desormais lui aussi contributeur de ce meme fichier)
avait deja ajoute sa propre regle avant que `WAZ_025` ne tourne, ce
dernier l'aurait ecrasee silencieusement. Corrige avec le meme principe
additif deja etabli par `WAZ_041_ALERT_CANARY.sh` (grep avant d'inserer,
jamais un `cat >` brut sur un fichier partage entre plusieurs jobs).

**Regression reelle introduite par le correctif ci-dessus, corrigee dans
la foulee** : le premier correctif de `WAZ_019_FLOOD.sh` (celui qui
ajoute la regle 100102) utilisait `sed -i 's#</group>#...#'` SANS
ancrage de ligne, en supposant a tort que `</group>` n'apparait qu'une
seule fois dans `local_rules.xml` (la fermeture du groupe englobant en
fin de fichier). Faux sur une VM fraiche : `local_rules.xml` est livre
par defaut avec un exemple (regle 100001, detection SSH) dont le tag de
classification interne (`<group>authentication_failed,pci_dss_10.2.4,
pci_dss_10.2.5,</group>`) se termine LUI AUSSI par `</group>`, sur sa
propre ligne, plus tot dans le fichier. Confirme en reel sur la VM
MIPREL : `sed` a remplace cette ligne-la (la premiere rencontree), pas
la fermeture finale - corrompant la regle 100001 existante (le texte de
la regle 100102 s'est retrouve concatene au milieu du tag de
classification de la 100001). Meme bug latent identifie par relecture
dans `WAZ_041_ALERT_CANARY.sh` (meme motif exact, ligne 70) - n'a pas
encore corrompu quoi que ce soit sur cette VM uniquement parce que ce
job (numerote 041, tout en fin de chaine) n'a pas encore tourne.
**Corrige** (`WAZ_019_FLOOD.sh`, `WAZ_025.sh`) : `sed -i '$s#</group>#...#'`
(adresse `$` = derniere ligne du fichier UNIQUEMENT, quel que soit le
nombre d'autres `</group>` ailleurs), plus une verification `grep`
explicite apres chaque ecriture (fichier ossec.conf ET local_rules.xml)
qui fait echouer le job avec un message clair si l'insertion n'a pas
reellement eu lieu - jamais suppose reussi. Meme session : `ossec.conf`
lui-meme n'avait PAS ete modifie du tout par le premier correctif (echec
silencieux d'un `sed` multi-lignes en guillemets doubles, `set -uo
pipefail` sans `set -e` ne detecte pas un `sed` qui echoue sans modifier
le fichier) - remplace par une insertion `awk` (variable passee
proprement via `-v`, aucune fragilite d'echappement de guillemets/
retours a la ligne) avec la meme verification `grep` obligatoire apres
coup.

**Encore une regression, corrigee dans la foulee** : meme apres le
correctif ci-dessus, l'ecriture dans `ossec.conf` echouait toujours en
reel (`cp: impossible de creer le fichier standard '...': Operation non
permise`). `lsattr` confirme : `----i---------------` - le fichier est
verrouille en immuable (`chattr +i`), un geste **volontaire** de
durcissement deja pose par `WAZ_014E_INDEXER_CONNECTOR.sh` (execute
plus tot dans cette meme session) et par `WAZ_032.sh`, PAS un accident.
`WAZ_019_FLOOD.sh` ne le savait pas et n'avait aucun mecanisme pour
gerer ce cas. **Corrige** avec exactement le meme geste deja etabli par
`WAZ_014E_INDEXER_CONNECTOR.sh` (seul autre job du projet a devoir deja
gerer ce cas) : detection via `lsattr` avant d'ecrire, `chattr -i`
temporaire si necessaire, puis `chown root:wazuh` + `chmod 640` +
`chattr +i` systematique en sortie - jamais laisser le fichier
deverrouille.

**Dernier maillon de la chaine WAZ_020_VERIFY, trouve apres verification
complete du pipeline** : le manager generait bien de vraies alertes
localement (6140 confirmees dans `alerts.log`/`alerts.json`, SELinux
correct), mais rien n'arrivait dans wazuh-indexer. `journalctl -u
logstash` montrait en boucle `Could not fetch URL
https://127.0.0.1:9200/... Connexion refusee`. Cause trouvee dans le
code : `jobs/WAZ_014B_ALERTS_TO_INDEXER.sh` ligne 45,
`WAZ_INDEXER_PORT="${WAZ_INDEXER_PORT:-9200}"` - valeur par defaut
fausse (9200, le port Elasticsearch classique), alors que
`WAZ_014A_INDXR_ADMINPW.sh` et `WAZ_020_VERIFY.sh` utilisent tous deux
`:-9201` par defaut pour cette meme variable (le vrai port REST de
wazuh-indexer sur cette usine). Incoherence introduite lors de l'ajout
de `WAZ_014B` (2026-08-30), jamais alignee avec les deux autres jobs qui
utilisent la meme variable. **Corrige** : `:-9201`, comme ses deux
jobs freres.

**Correctif ci-dessus incomplet, corrige honnetement dans la foulee -
la vraie cause etait ailleurs.** Apres avoir pousse le correctif de port
et confirme sa presence sur la VM, Logstash visait TOUJOURS le port
9200 en pratique. Verification faite (pas supposee) : `vars.conf`
definit explicitement `WAZ_INDEXER_PORT=9200` (ligne 450) - cette
valeur explicite prime TOUJOURS sur un `${VAR:-defaut}` dans n'importe
quel job, donc le correctif de port ci-dessus n'a jamais eu d'effet
reel (inoffensif, mais base sur une supposition non verifiee - le
`:-9201` des jobs "freres" ne s'appliquait deja pas non plus en
pratique). 9200 est le vrai port REST de wazuh-indexer sur cette usine.
La vraie cause du "Connexion refusee" : **`wazuh-indexer` etait
completement en panne** (`systemctl status` : "failed (Result:
timeout)"), independamment de tout numero de port. `journalctl -u
wazuh-indexer` a revele l'erreur reelle : `java.security.
AccessControlException: access denied (java.lang.RuntimePermission
setContextClassLoader)` pendant l'initialisation de log4j - le fichier
de politique de securite JVM du module Performance Analyzer
(`/etc/wazuh-indexer/opensearch-performance-analyzer/
opensearch_security.policy`) n'accorde jamais cette permission (verifie
intact, non corrompu : taille/date d'origine du paquet inchangees,
confirme par `rpm -V`) - un defaut de compatibilite du produit
wazuh-indexer 4.14.7 lui-meme, pas une erreur de configuration de cette
usine. **Corrige** : ajout de la permission manquante au fichier de
politique (correctif standard documente pour cette classe
d'AccessControlException sur les produits bases OpenSearch), verifie en
reel - `wazuh-indexer` redemarre et reste actif, port 9200 en ecoute
confirme (`ss -tlnp`). Applique aussi dans `WAZ_014.sh`
(WEF_WAZ_BLD_STARTINDXR, le job qui demarre wazuh-indexer) AVANT la
premiere tentative de demarrage, pour qu'un futur deploiement propre
(VM fraiche, meme version du paquet) n'entre jamais dans cette boucle
de crash. **Resultat final verifie** : chaine complete WAZ_014B ->
WAZ_019_FLOOD -> WAZ_020_VERIFY rejouee de bout en bout avec succes
reel - `WAZ_020_VERIFY -> OK (WAZ_INDEX_OK)`, confirme par le marqueur
d'etat de l'orchestrateur, pas suppose.

**WAZ_022 (secret operateur, pas un bug de job)** : `secrets/
wazuh_api_password.txt` absent sur cette VM (fraiche pour ce cycle de
deploiement). Le job lit ce secret en lecture seule par conception (son
propre en-tete l'explique : en generer un ici casserait
l'authentification au lieu de la reparer, aucun job de cette usine ne
pousse ce mot de passe cote wazuh-apid). Verifie en reel : les
identifiants par defaut du paquet `wazuh-manager` pour une installation
RPM manuelle (`wazuh`/`wazuh`, PAS d'auto-generation contrairement a
l'assistant d'installation tout-en-un) fonctionnent toujours -
confirme par un vrai jeton JWT recu via `/security/user/authenticate`.
Secret cree en consequence (`echo -n 'wazuh' > secrets/
wazuh_api_password.txt`, chmod 600). A changer par l'operateur en
production reelle (identifiants par defaut, jamais a garder tels quels
hors environnement de test).

**Incident de la coupure VM (04:39-04:48) : cause trouvee par la suite,
en reel, pas seulement soupçonnee.** Laisse d'abord ouvert faute de
preuve suffisante (voir plus haut : `vmware.log` montrait des ecritures
disque anormalement lentes, 1,4 a 2,8 secondes par commande WRITE, mais
sur une fenetre horaire qui ne recouvrait pas exactement la coupure).
Confirmation reelle obtenue une heure plus tard, meme session : VMware
Workstation a affiche en direct "The operation on the file
'...Oracle Linux 8 64-bit-000001-s009.vmdk' failed (Espace insuffisant
sur le disque)" - **le disque physique du PC hote etait plein**. Cause
racine du "crash" initial ET des ecritures lentes observees plus tot
(un disque presque plein degrade fortement les performances d'ecriture
avant meme d'etre totalement plein). Facteur aggravant identifie : un
**snapshot VMware actif** sur cette VM, dont le disque differentiel
grossit a chaque ecriture (une quinzaine de fichiers
`-000001-s0XX.vmdk`, plusieurs dizaines de Go cumules) - explique a la
fois la croissance rapide de l'espace disque au fil de cette session ET
le ralentissement des ecritures (un disque differentiel est plus lent
qu'un disque plat). Deblocage immediat : suppression de 2 VM inutilisees
par l'operateur (89,4 Gio liberes), operation reprise avec succes.
Recommandation laissee a l'operateur (pas d'action prise sans son
accord) : supprimer le snapshot une fois le deploiement stabilise et
verifie, pour recuperer l'espace et retrouver des performances
d'ecriture normales - un snapshot actif de tres longue duree sur une VM
qui ecrit beaucoup (comme un deploiement complet ELK/Wazuh) n'est pas un
usage sain de cette fonctionnalite.

## Prochaine etape

Execution reelle contre les 2 VM (`./orchestrator.sh` sur chaque machine,
avec `ROLE=ELK_HOST` sur VM1 et `ROLE=AGENT_HOST` +
`AGENT_COMPONENTS="FILEBEAT,METRICBEAT,WAZUH_AGENT,HOSTNAME_RENAME"` sur
VM2), impossible a valider contre le vrai cluster depuis ce bac a sable
faute d'acces reseau vers 192.168.50.128/.129 - mais la resolution de
dependances elle-meme (l'ordonnancement des 241 jobs) est maintenant
verifiee reellement (voir "Bugs trouves..." plus haut), pas juste
supposee correcte.
