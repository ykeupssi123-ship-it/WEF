> **Lecture optionnelle / approfondie.** Ce document est le journal technique
> complet du projet : chaque bug réel rencontré, sa cause exacte, son
> diagnostic et son correctif, dans l'ordre chronologique. Il n'est **pas**
> nécessaire pour installer ou exploiter le produit — voir
> [`README.md`](../README.md) et [`GUIDE_EXPLOITATION.md`](GUIDE_EXPLOITATION.md)
> à la racine pour ça. Gardé ici pour la profondeur d'ingénierie qu'il
> démontre (utile pour une soutenance, un audit, ou pour quiconque doit un
> jour modifier ce code en connaissance de cause).
>
> **Noms d'outils historiques (avant le 4 septembre 2026)** : les entrées
> ci-dessous mentionnent `forcer_job.sh`, `geler_job.sh`, `liberer_job.sh`,
> `marquer_deja_fait.sh`, `historique_job.sh`, `statut_live.sh` à la racine
> - c'était exact et vrai au moment de chaque incident decrit, jamais
> corrigé après coup pour rester un compte-rendu fidèle. Depuis cette date,
> ces outils vivent dans `bin/` sous leur vrai nom Control-M
> (`bin/order.sh`, `bin/hold.sh`, `bin/free.sh`,
> `bin/confirm.sh`, `bin/history.sh`, `bin/monitor.sh`) - voir
> `README.md` pour la table de correspondance complète et le diagnostic de
> cette réorganisation.

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
orchestrator.sh lui-meme (`notify.sh`, `statut_live.sh`,
`historique_job.sh`, `resume.sh`...). Consequence reelle
observee : `./notify.sh --test` a echoue avec "Permission non
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

## Reinitialisation du mot de passe `elastic` (`reset_es_password.sh`)

Ajoute le 2026-08-14 suite a l'incident 9 ci-dessus. Avant ce script, la
reparation d'un mot de passe `elastic` desynchronise exigeait une
sequence de commandes tapees a la main (`elasticsearch-reset-password`,
puis recopier la valeur au bon endroit, avec les bons droits) - source
d'erreur reelle et rien de reproductible a documenter pour un client.
Desormais :

- **Un seul point d'entree sanctionne** : `./reset_es_password.sh`
  (ou `wpwreset` via `profile.sh`). Aucune autre procedure ne
  doit etre utilisee pour toucher ce mot de passe.
- **Une seule reference** : `state/es_bootstrap_password.secret` reste LA
  valeur canonique - le script l'ecrase avec la nouvelle valeur et
  personne d'autre n'a besoin d'etre mis a jour a la main. Tout ce qui
  consomme ce mot de passe (`es_admin_curl`, `escreds` dans
  `profile.sh`) le relit directement depuis ce fichier a chaque
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
    `es_admin_curl`/`reset_es_password.sh` (incident 9) est deja
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

- **`./resume.sh`** (a lancer AVANT `orchestrator.sh`, en
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

`./audit.sh` donne la vue d'ensemble (tous les jobs ayant un
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
`historique_job.sh <JOB_ID> stats` et `audit.sh` comptent ces
forcages dans les totaux de reussite/echec mais signalent toujours
combien d'executions etaient des forcages manuels.

Teste : job inconnu (erreur propre), job deja termine avec succes
(aucune execution, message explicite), mauvaise confirmation (annule,
rien dans le registre), et forcage reussi (script reellement execute
malgre la dependance manquante, `.ok` cree, marqueur EN_COURS nettoye,
ligne `FORCE_OK` dans le registre, bien comptabilisee par
`historique_job.sh` et `audit.sh`).

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

Raccourci une fois `profile.sh` source : `wskip <JOB_ID>
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

## Alerte par email sur echec de job (notify.sh)

Ajoute le 2026-08-12. Le plus gros manque reel face a un centre
d'exploitation 24/7 : sans ca, un job qui echoue ne fait qu'ecrire un
log - personne n'est prevenu tant qu'un humain ne va pas le lire.
`orchestrator.sh` et `forcer_job.sh` appellent desormais `notify.sh`
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
`vars.conf` (ou il est defini) et `notify.sh` (ou il est lu, une
seule fois, `notify.sh:55` : `SMTP_PASS="$(cat "$SMTP_PASS_FILE")"`)
- confirme par `grep -rn SMTP_PASS_FILE jobs/ lib/ orchestrator.sh`
(aucun resultat). Basculer vers un vault ou une variable
d'environnement se limite donc a remplacer cette seule ligne par
l'appel au coffre-fort ou une lecture de variable : aucun job, aucun
autre script du projet ne reference ni ne suppose l'existence d'un
fichier de mot de passe, donc aucune regression possible ailleurs.

Test independant de toute panne reelle : `./notify.sh --test`.

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
vraie limite, corrigee le 2026-08-12. `notify.sh` forcait au depart
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
confirmer avec un envoi `./notify.sh --test` reel le jour ou un tel
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

## Vocabulaire operateur (`profile.sh`)

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
. /chemin/vers/wazuh_factory_3/profile.sh
```
Pour l'avoir a chaque connexion, une seule fois :
```
echo '. /chemin/vers/wazuh_factory_3/profile.sh' >> ~/.bashrc
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
| `wpwreset` | Raccourci vers `./reset_es_password.sh` - seul point sanctionne pour reinitialiser le mot de passe `elastic` (voir section dediee) |
| `wskip <JOB_ID> "<raison>"` | Raccourci vers `./marquer_deja_fait.sh` - marque un job deja satisfait sans l'executer, sans bloquer ce qui en depend (voir section dediee) |

**Adaptation a la nomenclature d'un client.** Un client peut deja avoir
sa propre convention de nommage pour ce type d'outillage. Tout le
vocabulaire est regroupe dans un seul bloc, clairement delimite, en bas
de `profile.sh` ("VOCABULAIRE OPERATEUR") - c'est le **seul**
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

## Refonte complete de la bascule Kibana<->Wazuh (2026-09-03, demande explicite utilisateur)

**Constat de depart** : l'ancien `WAZ_035_MODE_CONVERGENT.sh`/
`WAZ_039_MODE_SOUVERAIN.sh` (monolithiques, un seul gros script par
sens) ne correspondaient plus a ce que l'utilisateur voulait
reellement :
  1. wazuh-indexer restait TOUJOURS actif en mode Kibana (choix
     deliberement documente le 2026-08-31, pour ne pas casser WAZ_014D/
     WAZ_014E/WAZ_042/WAZ_043/INFRA_004_HEALTH_GUARDIAN qui en
     dependent) - l'utilisateur veut au contraire un mode EXCLUSIF ou
     wazuh-dashboard ET wazuh-indexer sont reellement arretes.
  2. La migration d'historique etait une COPIE (scroll+bulk), jamais
     une COUPURE - la source restait peuplee des deux cotes.
  3. Chaque bascule etait UN SEUL job - impossible de geler
     individuellement une seule etape (ex: juste la coupure de donnees)
     via SKIP_JOBS sans geler toute la bascule.

**Decisions prises avec l'utilisateur (AskUserQuestion, 2026-09-03)** :
  - Les jobs dependants de wazuh-indexer sont mis en pause pendant le
    mode Kibana (SKIP_JOBS pour WAZ_014D/WAZ_014E/WAZ_042/WAZ_043) et
    reactives au retour. CAS A PART trouve en verifiant le code :
    INFRA_004_HEALTH_GUARDIAN n'est PAS repris par SKIP_JOBS (c'est un
    INSTALLATEUR one-shot d'un timer systemd independant qui ne
    consulte jamais SKIP_JOBS) - suspendu/reactive directement via
    `systemctl stop/start wef-health-guardian.timer`.
  - "Couper" signifie reellement supprimer les documents source apres
    verification stricte que la copie est complete (jamais de
    suppression optimiste - voir jobs/lib/cut_migrate.sh).
  - L'ancien WAZ_037_CONVERGENT_TEST (qui echouait ce soir-la) est
    remplace par la nouvelle chaine plutot que diagnostique isolement.

**Nouvelle architecture** (chaque etape = un job independant,
individuellement gelable via SKIP_JOBS, meme convention de nommage que
le reste du projet) :

Bascule vers Kibana (remplace WAZ_035_MODE_CONVERGENT.sh) :
`WAZ_035_KIBANA_TRIGGER` (point d'entree, rejouable via forcer_job.sh) ->
`WAZ_035A_PAUSE_DEP_JOBS` -> `WAZ_035B_CUT_INDEXER_TO_ES` (coupure
reelle) -> `WAZ_035C_REROUTE_PIPELINE_ES` -> `WAZ_035D_STOP_WAZUI`
(arret reel de wazuh-dashboard ET wazuh-indexer, ecrit
WAZ_ALERTS_ROUTE.state=ELASTICSEARCH) -> WAZ_036/037/038 (inchanges).

Retour vers Wazuh (remplace WAZ_039_MODE_SOUVERAIN.sh) :
`WAZ_039_WAZUH_TRIGGER` -> `WAZ_039A_START_WAZUI` (redemarre
wazuh-indexer PUIS wazuh-dashboard) -> `WAZ_039B_REROUTE_PIPELINE_INDEXER`
-> `WAZ_039C_CUT_ES_TO_INDEXER` (coupure reelle inverse) ->
`WAZ_039D_RESUME_DEP_JOBS` (leve SKIP_JOBS + reactive le timer, ecrit
WAZ_ALERTS_ROUTE.state=INDEXER) -> WAZ_040/041 (inchanges).

Seul `WAZ_036_KIBANA_INDEX` (IN_COND) a du etre touche parmi les jobs
existants deja eprouves - tout le reste de la chaine (037/038/040/041)
garde EXACTEMENT les memes noms de marqueurs qu'avant, zero autre
modification necessaire.

**Nouveaux outils partages** (`jobs/lib/`) :
  - `cut_migrate.sh` : logique scroll+bulk (reprise a l'identique du
    code deja PROUVE fonctionnel du 2026-08-31) + etape de suppression
    source ajoutee, jamais tentee avant confirmation stricte que le
    compte destination >= compte source.
  - `skip_jobs_toggle.sh` : ajout/retrait cible de JOB_ID precis dans
    SKIP_JOBS (vars.conf), jamais les autres entrees deja presentes
    (ex. `SKIP_JOBS="ES_001"` de base) - sauvegarde + verification apres
    coup, meme discipline que chaque edition de fichier critique cette
    nuit.
  - `test_data_tools.sh` : `seed_test_alerts` (charge un volume
    configurable - defaut 50000, `WAZ_SEED_COUNT` - de documents
    synthetiques marques `"wef_test_seed": true`, jamais confondus avec
    une vraie alerte) et `purge_index_pattern` (delete_by_query +
    verification stricte a 0 apres coup).

**Nouveaux jobs de test/nettoyage** (demande separee de l'utilisateur,
JAMAIS dans la chaine automatique - `IN_COND=WAZ_PURGE_MANUAL_GATE`,
une condition qu'aucun job ne produit jamais - usage EXCLUSIVEMENT via
`forcer_job.sh`, qui tolere un IN_COND non satisfait apres confirmation
explicite tapee par l'operateur) : `WAZ_045A_SEED_INDEXER_DATA`,
`WAZ_045B_SEED_ES_DATA`, `WAZ_046_PURGE_INDEXER_DATA` (destructeur,
irreversible), `WAZ_047_PURGE_ES_DATA` (destructeur, irreversible).

**BUG REEL TROUVE ET CORRIGE avant meme le premier test en direct** : le
parseur CSV de ce projet (`orchestrator.sh`, `forcer_job.sh` : simple
`read -r ... IFS=','`, aucune gestion de guillemets) casse des qu'un
champ DESC contient une virgule litterale - un texte comme "coupe, non
copie" aurait decale IN_COND/OUT_COND de deux jobs et corrompu
silencieusement leur chainage de dependances. Trouve par verification
systematique (`awk -F',' 'NF!=8'` sur tout `jobs_table.csv`) avant de
livrer, jamais suppose correct - convention du projet confirmee :
utiliser un tiret "-", jamais une virgule, dans une description.

**PAS ENCORE TESTE EN REEL sur la VM** (contrairement au reste de cette
nuit) - a verifier au premier `./orchestrator.sh` : la cascade complete
vers Kibana, le retour vers Wazuh, et separement les jobs de
seed/purge. Honnete : la syntaxe bash de chaque script est verifiee
(`bash -n`), mais la logique Python embarquee (scroll+bulk+delete,
bulk-seed) n'a pu etre testee que par relecture (aucun interpreteur
Python disponible sur la machine Windows locale) - premiere execution
reelle a surveiller de pres.

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

## 2026-09-08 - WAZ_014 echoue sur deploiement MIPREL2 (VM 192.168.50.128) : 120s insuffisant sous pression memoire reelle

**Incident reel** : `./orchestrator.sh` (clone frais depuis GitHub, commit `6c52f96`) echoue a `WAZ_014` apres avoir installe avec succes ES/Logstash/Kibana puis Wazuh Indexer sur la meme VM (`ROLE=ELK_HOST`, `RESOURCE_PROFILE=DEMO_LEGER`). Log reel (`state/history/WAZ_014/20260908_054323_943825653.log`) : `systemctl restart wazuh-indexer` a mis 58s pour que systemd considere l'unite "Started" (05:43:23 -> 05:44:21), puis l'API a repondu HTTP 503 pendant l'integralite des 120s de sondage alloues par le correctif du 2026-09-04 - jamais 200/401.

**Diagnostic reel** (`free -h` et `systemctl status wazuh-indexer` demandes a l'operateur) : `systemctl status` montre le service **actif et sain** quelques heures plus tard (`active (running)... 9h ago`, aucune erreur, Memory 1.1G) - donc pas un crash ni une corruption, juste un demarrage plus lent que le budget de 120s. `free -h` au moment de la demande de diagnostic : 5,6 Gio total, seulement 1,4 Gio "available" (ES 768m heap + Logstash 768m heap + Kibana + l'indexeur 768m heap deja tous residents sur une seule VM en profil DEMO_LEGER). HTTP 503 (pas 000/connexion refusee) = le plugin de securite OpenSearch est en cours d'initialisation, pas en echec - ce bootstrap est connu pour ralentir fortement sous pression memoire/swap.

**Corrige** : `WAZ_014.sh` - budget de sondage remonte de 120s (fixe en dur) a `WAZ_INDEXER_READY_TIMEOUT_SEC` (nouvelle variable `vars.conf`, defaut 300s), diagnostic d'echec enrichi d'un `free -h` reel (avant meme `journalctl`) pour que le prochain incident de ce type se diagnostique en un seul log, sans aller-retour. Deblocage immediat de l'operateur : l'API repondant deja normalement, un simple `./orchestrator.sh` relance passe WAZ_014 sans attente (job deja idempotent, aucun autre changement necessaire).

**Non fait, deliberement** : ni augmentation de RAM allouee a la VM, ni reduction des heaps JVM deja au plancher du profil DEMO_LEGER (768m chacun) - la vraie cause est la co-residence de 3 JVM + Kibana sur une VM a 4-6 Gio, caracteristique connue et documentee de ce profil (`RESOURCE_PROFILE="DEMO_LEGER"`), pas une anomalie a corriger en dur dans le code.

## 2026-09-08 (suite) - Cause racine reelle de WAZ_014 : 1 seul vCPU, pas seulement la RAM - nouveau controle ES_B001B_CPU_CHECK

**Deuxieme occurrence du meme incident** apres le correctif de budget (300s) : `WAZ_014` echoue encore, HTTP 503 permanent (`OpenSearch Security not initialized`) meme apres ~4 minutes. Diagnostic pousse plus loin sur demande, reel :
- `nproc` -> **1** (un seul vCPU).
- `uptime` -> `load average: 2.01, 1.95, 1.17` sur cette unique VCPU - contention CPU severe et soutenue, pas un pic isole.
- `ps aux --sort=-%cpu` -> Elasticsearch (java), Logstash (java), Kibana (node) et Wazuh Indexer (java) tous actifs SIMULTANEMENT sur le meme coeur unique.
- `free -h` -> RAM disponible correcte (1,5 Gio) - **la RAM n'est pas le facteur limitant ici**, contrairement a l'hypothese initiale du correctif precedent.

**Cause reelle** : 4 JVM/runtimes lourds se disputent 1 seul coeur CPU. Le bootstrap du plugin de securite OpenSearch (generation de cles, creation d'index systeme `.opendistro_security`) est CPU-bound - sous contention severe et soutenue, il peut prendre plusieurs minutes au lieu de quelques secondes. Ce n'est PAS un bug du produit ni une histoire de delai a rallonger indefiniment : c'est un sous-dimensionnement reel de la VM, invisible jusqu'a ce point precis de la chaine (aucun controle vCPU n'existait pour le role ELK_HOST avant ce jour - seul `MIN_VCPU_REQUIRED_AGENT` existait, pour AGENT_HOST).

**Corrige** : nouveau job `ES_B001B_CPU_CHECK` (`jobs/ES_B001B_CPU_CHECK.sh`), insere juste apres `ES_B001_RAM_CHECK` dans `jobs_table.csv` (`ES_002` repointe sur son `OUT_COND`, `ES_CPU_CONFIRMED`, au lieu de `ES_RAM_CONFIRMED` directement) - meme patron exact que le controle RAM. Nouveau seuil `MIN_VCPU_REQUIRED=2` (`vars.conf`). Desormais, une VM ELK_HOST a 1 seul vCPU echoue proprement des le debut de la chaine, avec un message qui explique pourquoi (4 JVM/runtimes en parallele) et quoi faire (ajouter un vCPU), au lieu d'un timeout mysterieux 30+ minutes plus tard sur `WAZ_014`.

**Non fait** : pas de modification du budget `WAZ_INDEXER_READY_TIMEOUT_SEC` (reste a 300s, ajoute plus haut le meme jour) - il reste une securite raisonnable pour une lenteur ponctuelle, mais n'est plus la premiere ligne de defense contre un sous-dimensionnement CPU reel, desormais interceptee en amont.

**Recommandation laissee a l'operateur** (VM locale VMware Workstation, pas d'action prise sans son accord) : eteindre la VM, augmenter le nombre de processeurs virtuels a 2 minimum dans les parametres VMware, redemarrer, puis relancer `./orchestrator.sh` (idempotent - reprend a `ES_B001B_CPU_CHECK`, tout le reste deja `OK` est saute).

## 2026-09-08 (suite, correction de fond) - WAZ_014 attendait un etat que seul WAZ_014A peut creer : "no such index [.opendistro_security]" persiste indefiniment, ce n'est pas de la lenteur

**Le diagnostic CPU (ES_B001B_CPU_CHECK, entree precedente) etait reel et corrige a raison, mais insuffisant** : apres avoir monte la VM a 2 vCPU (confirme reel : `nproc`=2, `lscpu` 2 sockets, load average redescendu a 0,15-0,86), `WAZ_014` echoue A NOUVEAU, exactement pareil (503 permanent). Diagnostic pousse jusqu'au vrai log applicatif (`/var/log/wazuh-indexer/wazuh-cluster.log` - JAMAIS journalctl, qui ne capture que la sortie JVM generique, pas le detail interne d'OpenSearch) :

```
[ERROR][o.o.s.c.ConfigurationLoaderSecurity7] Failure no such index [.opendistro_security] retrieving configuration for [...]
```

Ce message se repete **indefiniment**, toutes les ~13s, verifie sur plus de 20 minutes consecutives, CPU et RAM normaux entre-temps (charge redescendue). Ce n'est PAS une lenteur de demarrage : **l'index systeme de securite n'existe simplement pas encore**, et rien dans `WAZ_014` ne le cree. Il n'est cree que par `securityadmin.sh` (via `wazuh-passwords-tool.sh`), qui vit dans `WAZ_014A_INDXR_ADMINPW.sh` - lequel ne peut jamais s'executer tant que `WAZ_014` (qui attend HTTP 200/401, jamais 503) n'a pas d'abord reussi. **Un vrai probleme d'oeuf et de poule architectural** : chaque tentative de deploiement de cette session (la toute premiere incluse, avant meme le premier correctif CPU/timeout) a echoue pour cette exacte raison - aucun budget d'attente, si genereux soit-il, n'aurait jamais resolu la situation.

**Correction reelle du diagnostic precedent** : l'hypothese "pression memoire ralentit le bootstrap du plugin de securite" (entree du 2026-09-08, correctif 120s->300s) etait une conclusion prematuree tiree d'un seul indice (`free -h` serre au moment de l'echec) sans avoir lu le vrai log applicatif - corrigee ici avec la preuve directe. Le correctif CPU (`ES_B001B_CPU_CHECK`) reste legitime et conserve (1 vCPU est reellement insuffisant pour cette pile), mais n'etait pas la cause de CET echec precis.

**Corrige** : `WAZ_014.sh` accepte desormais HTTP `503` comme preuve de vie valide (en plus de `200`/`401`) - 503 prouve que le demon a demarre et que son plugin de securite est charge et repond reellement (contrairement a une connexion refusee/timeout, qui prouverait l'inverse) ; il attend seulement son initialisation, qui reste explicitement le role de `WAZ_014A` (lequel verifie lui-meme, par un appel authentifie reel a `_cluster/health`, que l'initialisation a reellement reussi avant de se declarer OK - rien n'est delegue a l'aveugle). Diagnostic d'echec enrichi du vrai log applicatif (`tail /var/log/wazuh-indexer/*.log`), pas seulement `journalctl`.

**Non verifie a ce stade** (a confirmer par l'operateur au prochain lancement) : que `WAZ_014A_INDXR_ADMINPW.sh` initialise correctement l'index de securite depuis cet etat "jamais initialise" via `wazuh-passwords-tool.sh` - le script est concu pour ce cas precis (c'est son usage principal documente), et les 3 incidents anterieurs (2026-08-20, 2026-09-03, 2026-09-04) confirment tous un aboutissement reel ("cluster GREEN") par ce meme mecanisme, mais jamais depuis un index totalement absent dans le cadre de cette session precise.

## 2026-09-08 (suite) - WAZ_014A echoue sur un index de securite fraichement cree (vierge) : le rechargement de config par defaut etait mal conditionne

**Suite directe de l'entree precedente** : une fois `WAZ_014` corrige (accepte 503), `WAZ_014A_INDXR_ADMINPW` echoue a son tour, reel (log de `wazuh-passwords-tool.sh`, `/opt/wef/state/tmp/waz014a_pwtool.log`) :

```
.opendistro_security index does not exists, attempt to create it ... done (0-all replicas)
Will retrieve '/internalusers' into /etc/wazuh-indexer/backup/internal_users.yml
   FAIL: Configuration for 'internalusers' failed because of empty source
...
ERROR: The given user does not exist
```

**Cause reelle** : `wazuh-passwords-tool.sh` fait un `securityadmin -backup` PUIS restaure avant de changer le mot de passe - concu pour FAIRE TOURNER le mot de passe d'un utilisateur DEJA existant, jamais pour amorcer un index totalement vierge (il vient d'etre cree par l'outil lui-meme a l'instant, sans aucune config dedans - donc rien a sauvegarder, "empty source" partout, et "admin" n'existe pas encore). Le correctif deja en place (`securityadmin.sh -cd`, qui pousse la config locale par defaut dans l'index) existait deja dans `WAZ_014A.sh` depuis le 2026-09-03 - mais sa condition de declenchement verifiait uniquement si le FICHIER LOCAL `internal_users.yml` etait vide. Ici, le fichier local etait intact (config demo standard, jamais modifiee) - c'est l'INDEX COTE SERVEUR qui etait vierge, un scenario different que la condition existante ne couvrait pas.

**Corrige** : le rechargement `securityadmin.sh -cd` est desormais INCONDITIONNEL - toujours execute avant `wazuh-passwords-tool.sh`, plus seulement quand le fichier local est vide. Couvre les deux scenarios reels rencontres (fichier local vide -> restauration RPM puis -cd ; index serveur vierge avec fichier local intact -> -cd directement) avec un seul mecanisme, idempotent par construction (repousser une config deja correcte ne change rien).

**A confirmer par l'operateur** : que `git pull && ./orchestrator.sh` fait desormais passer `WAZ_014A` proprement (le `-cd` initialise l'index, puis `wazuh-passwords-tool.sh` trouve un utilisateur "admin" reel a faire tourner).

## 2026-09-09 - Reorganisation : les gardes de resilience protegent desormais des le debut de la chaine, pas a la fin

**Demande explicite** : suite a l'incident reel du jour (disque hote plein -> VM coupee -> /dev/null corrompu -> SSH inaccessible pendant plusieurs minutes, decouvert en plein milieu du deploiement) - reorganiser `jobs_table.csv` pour que les mecanismes de resilience protegent DES LE DEBUT, pas seulement une fois forces a la main (`bin/order.sh`) apres coup.

**Constat reel** : `INFRA_003_DEVNULL_GUARDIAN` (timer /dev/null 3s), `INFRA_004_HEALTH_GUARDIAN` (controle sante 5 min - services/DNS/certificat/disque), `INFRA_005_DISK_HYGIENE` (nettoyage + entretien hebdomadaire) et `INFRA_001` (renommage VM) etaient tous places aux lignes 255-259 d'un fichier de 271 lignes - soit apres environ 94% de la chaine complete (PKI, ES, LS, KB, WAZ_001 a WAZ_042+). Consequence directe : ces protections n'etaient actives QUE dans les tout derniers jobs d'un deploiement complet - zero protection pendant la quasi-totalite de la chaine, exactement le moment ou les operations les plus lourdes/instables se produisent (installations de paquets, redemarrages de services, le crash-test reseau WAZ_018_NET).

**Verifie avant deplacement (jamais suppose)** : les 4 jobs ont `IN_COND=NONE` (aucun prerequis) et AUCUN autre job du projet ne consomme leurs `OUT_COND` (`ELK_HOSTNAME_SET`, `DEVNULL_GUARDIAN_OK`, `HEALTH_GUARDIAN_OK`, `DISK_HYGIENE_OK` - grep exhaustif sur toute la colonne IN_COND) - deplacement topologiquement sans risque, confirme par un diff trie avant/apres montrant un contenu strictement identique, seulement reordonne.

**Corrige** : les 4 jobs deplaces en tete de `jobs_table.csv`, juste apres l'en-tete, avant meme `PKI_001`. Desormais actifs des la premiere seconde de tout deploiement (`orchestrator.sh` lit le fichier sequentiellement, une seule passe - l'ordre des lignes fait foi). Bruit attendu et accepte le temps que les services reels existent (`INFRA_004` journalisera des alertes "service non actif" avant que ES/Wazuh ne soient installes) - un faux positif journalise vaut mieux qu'une absence totale de surveillance.

**Corrige egalement (`orchestrator.sh`)** : avertissement ajoute au tout debut de l'execution si le script ne tourne PAS sous systemd (`$INVOCATION_ID` absent, variable que systemd exporte a tout processus qu'il supervise directement) - rend visible, des la premiere ligne de log et quel que soit l'endroit ou la chaine se bloque ensuite, le risque deja documente le 2026-08-19 (`setup/installer_service_orchestrateur.sh`) qu'une coupure reseau/deconnexion tue l'orchestrateur en plein milieu s'il tourne en direct dans une session SSH. Avertissement seulement, jamais un blocage - un lancement direct reste legitime pour un test court.

## 2026-09-09 (suite) - WAZ_020_VERIFY : le manager generait bien les alertes, l'acheminement avait juste besoin de plus de temps

**Suite du meme deploiement** (VM renommee `wef-elk-core` par `INFRA_001`, desormais en tete de chaine) : `WAZ_020_VERIFY` echoue encore apres les 4 gardes de resilience, toujours 0 alerte indexee.

**Diagnostic reel, en ecartant les fausses pistes une a une** :
- `WAZ_019_FLOOD` avait bien reussi (log confirme : fichier `/var/log/wazuh-flood-test.log` a 20000 lignes, regle 100102 posee, wazuh-manager redemarre).
- Le manager avait bien DETECTE le deluge : `grep -c "100102" /var/ossec/logs/alerts/alerts.log` -> **3862** occurrences reelles.
- La vraie panne : `systemctl status logstash` montrait `logstash.outputs.http ... Connect to 127.0.0.1:9200 ... Connexion refusee` - le pipeline dedie `WAZ_014B_ALERTS_TO_INDEXER` echouait a livrer vers l'indexeur.
- Relu `WAZ_014B_ALERTS_TO_INDEXER.sh` en entier avant de conclure a un bug de configuration : le port cible (`WAZ_INDEXER_PORT`, resolu a 9200 via `vars.conf`, jamais le "9201" par defaut du script qui ne s'applique que si la variable etait absente) est le bon, deja confirme fonctionnel par `WAZ_014`/`WAZ_014A`/`WAZ_020_VERIFY` eux-memes. Pas une mauvaise configuration - l'indexeur devient transitoirement injoignable sous la charge deja documentee de cette VM (2 vCPU, 6 services JVM/Node simultanes), exactement la meme classe d'instabilite que l'incident `WAZ_014` du jour precedent.

**Corrige** : budget de `WAZ_020_VERIFY` remonte de 30s (6x5s) a `WAZ_INDEX_VERIFY_TIMEOUT_SEC` (nouvelle variable `vars.conf`, defaut 240s, pas de 10s) - laisse le temps a `retry_non_idempotent` (deja actif dans `WAZ_014B`) et a la Persistent Queue Logstash de livrer les documents en attente une fois l'indexeur stable. **Jamais rejoue `WAZ_019_FLOOD`** pour cet incident : le manager avait deja reellement produit les alertes, seul l'acheminement manquait de temps - rejouer l'injection aurait ete inutile et aurait gonfle le flood sans regler la vraie cause.

**Diagnostic d'echec enrichi** (pour que le prochain incident se lise en un seul log, sans aller-retour) : `WAZ_020_VERIFY` affiche desormais, en cas d'echec final, le compte reel d'alertes generees par le manager, les 15 dernieres lignes Logstash concernant le pipeline `wazuh-alerts`, et l'etat de `wazuh-indexer` - trois preuves directes au lieu de devoir les redemander une par une.

## 2026-09-09 (suite) - Cause racine finale trouvee : wazuh-indexer.service timeout systemd au boot, angle mort de l'idempotence

**Diagnostic definitif** (le "Connexion refusee" Logstash de l'entree precedente n'etait qu'un symptome) :
```
systemctl status wazuh-indexer --no-pager
● wazuh-indexer.service - wazuh-indexer
   Active: failed (Result: timeout) since Wed 2026-09-09 04:10:15 WAT; 1h 18min ago
 Main PID: 1494 (code=exited, status=143)
```
`journalctl -u wazuh-indexer --since "04:06" --until "04:11"` confirme : `wazuh-indexer.service: start operation timed out. Terminating.` a 04:10:13, exactement 3 minutes (`TimeoutStartUSec=3min`, valeur vendor) apres le debut du demarrage a 04:07:13 - la VM avait redemarre (`Logs begin at ... 04:06:59`), et wazuh-indexer, wazuh-manager, wazuh-dashboard, Elasticsearch, Logstash et Kibana ont tous tente de demarrer simultanement au boot sur 2 vCPU - le meme scenario de contention deja rencontre, mais cette fois assez severe pour depasser le delai systemd lui-meme, pas seulement le sondage HTTP applicatif de `WAZ_014.sh`.

**Precedent deja existant, jamais applique ici** : `WAZ_015.sh` (wazuh-manager) documente EXACTEMENT ce risque depuis le 2026-08-30, avec un drop-in `TimeoutStartSec=180` deja en place (`/etc/systemd/system/wazuh-manager.service.d/override.conf`, confirme present sur cette VM). Son propre en-tete anticipait meme explicitement que wazuh-indexer pouvait souffrir du meme probleme - jamais corrige a l'epoque cote indexeur.

**Angle mort reel decouvert par cet incident** : `WAZ_014` etait deja marque `.ok` (`WAZ_INDEXER_UP`) d'un run anterieur a ce redemarrage de VM - l'orchestrateur ne l'a donc jamais rejoue apres le boot, et n'a eu aucune occasion de detecter que le service avait echoue a redemarrer tout seul. Seul `INFRA_004_HEALTH_GUARDIAN` (installe le jour meme, desormais en tete de chaine) a detecte et journalise la panne, en continu, toutes les 5 minutes depuis son installation (`journalctl -t wef-health-guardian` : 9 alertes consecutives entre 04:57 et 05:37) - sans jamais la corriger lui-meme (choix deliberement documente : jamais d'action corrective automatique sur un service metier). Sans cette garde, la panne serait restee invisible indefiniment.

**Corrige** : `WAZ_014.sh` installe desormais le meme type de drop-in systemd que `WAZ_015.sh`, `TimeoutStartSec=300` (aligne sur `WAZ_INDEXER_READY_TIMEOUT_SEC`, deja prouve necessaire sous charge reelle) - survit aux redemarrages de VM ET aux mises a jour du paquet. Protege desormais le demarrage AUTOMATIQUE au boot par systemd (`enable`d), pas seulement celui declenche manuellement par ce job.

**Deblocage immediat verifie en reel** : `systemctl reset-failed wazuh-indexer && systemctl restart wazuh-indexer` - actif et repondant HTTP 401 en 15 secondes une fois la contention de demarrage a froid retombee (tous les autres services deja stables a ce moment).

**Limite honnete restante** : le nouveau drop-in protege les FUTURS demarrages (prochain boot, prochain deploiement neuf) mais ne s'applique pas retroactivement sur une VM ou `WAZ_014` est deja `.ok` - a appliquer manuellement une fois sur les VM deja deployees (voir commande de deblocage ci-dessus + creation manuelle du drop-in), ou en rejouant `WAZ_014` via `bin/order.sh`.

## 2026-09-09 (suite) - WAZ_022 : le defaut Wazuh reel automatise, jamais un mot de passe invente

**Incident reel** : `secrets/wazuh_api_password.txt` absent sur cette VM - `WAZ_022` echoue avec le message d'erreur deja honnetement documente depuis le 2026-08-30 (aucun job ne pousse ce mot de passe, le generer au hasard casserait l'authentification). Verifie en reel avec l'operateur avant de coder quoi que ce soit : `curl -u wazuh:wazuh -k -X POST https://127.0.0.1:55000/security/user/authenticate` -> vrai jeton JWT retourne - le defaut d'installation Wazuh (utilisateur `wazuh`, mot de passe `wazuh`) est bien actif sur cette instance.

**Corrige** : `WAZ_022.sh` tente desormais ce defaut connu UNE fois si le fichier est absent - jamais ecrit en aveugle, seule une authentification REELLEMENT reussie (meme fonction de verification qu'avant, un vrai appel `/security/user/authenticate` avec assertion sur le champ `data`) fait persister la valeur dans `secrets/wazuh_api_password.txt`. Si ce defaut a ete change par l'operateur sur une autre VM, le comportement retombe exactement sur l'erreur claire d'origine (jamais un mot de passe invente a la place). Ferme l'ecart entre "limite honnetement documentee" et "verifiee comme un vrai defaut d'installation reproductible" - sans jamais risquer de casser une instance ou ce defaut aurait deja ete change.

## 2026-09-09 (suite) - WAZ_035B_CUT_INDEXER_TO_ES : meme classe de contention, cette fois sur l'allocation de shard Elasticsearch

**Incident reel** : la bascule vers Kibana echoue au premier vrai transfert de donnees (8230 alertes deja confirmees cote wazuh-indexer par `WAZ_020_VERIFY`) :
```
ERREUR bulk (copie) : {'type': 'unavailable_shards_exception', 'reason': '[wazuh-alerts-4.x-2026.09.09][0] primary shard is not active Timeout: [1m], ...'}
```
**Cause reelle** : le tout premier lot `_bulk` vers Elasticsearch (jamais ecrit avant) declenche la creation automatique de l'index de destination - son shard primaire unique (cluster mono-noeud) n'a pas eu le temps de devenir actif sous la charge deja bien documentee de cette VM ce jour (2 vCPU, 6 services). Meme famille exacte d'incident que `WAZ_014`/`WAZ_020_VERIFY` - un composant du pipeline pas encore pret prend plus de temps que le code ne lui en laisse, jamais une vraie corruption de donnees.

**Verifie avant de corriger** : source jamais touchee (la suppression ne se declenche qu'apres verification stricte du compte destination, jamais atteinte ici) - aucun risque de perte, juste a rejouer.

**Corrige** (`jobs/lib/cut_migrate.sh`) : le lot `_bulk` en echec est desormais rejoue automatiquement (6 tentatives, 5s d'ecart) - UNIQUEMENT si TOUTES les erreurs du lot sont bien du type transitoire `unavailable_shards_exception` (toute autre erreur reelle, mapping incompatible ou document malforme, remonte immediatement, jamais masquee). Rejouer le meme lot est sans risque : un `_bulk` de type "index" avec les memes `_id` source ecrase, ne duplique jamais.

**Deblocage** : `bin/order.sh WAZ_035B_CUT_INDEXER_TO_ES` - source intacte, rejouable sans effet de bord.

## 2026-09-09 (suite) - Anticiper plutot que reagir : le disque plein etait deja programme des l'installation

**Demande explicite de l'utilisateur** : trop d'allers-retours manuels aujourd'hui pour le disque - anticiper ce probleme DANS les scripts orchestres, pour que le prochain deploiement depuis zero n'exige plus cette intervention.

**Cause racine, trouvee en repartant du tout debut** (`pvs`/`vgs`/`lvs`, deja consultes plus tot le meme jour) : le groupe de volumes LVM etait deja rempli a 100% (`VFree=0`) DES L'INSTALLATION - 35,6 Go pour `/`, 17,4 Go pour `/home`, 6 Go de swap, sur un disque de 60 Go. Aucun kickstart ou script de partitionnement ne fait partie de ce depot (partitionnement automatique Anaconda, hors du controle de cette usine) - le disque etait donc programme pour se remplir des le depart, independamment de l'incident VD (Vulnerability Detector) de la journee.

**Corrige** : nouveau job `INFRA_002_RECLAIM_HOME`, en tete de `jobs_table.csv` (avant meme `INFRA_001`) - fusionne `/home` dans `/` UNE FOIS, avant toute installation lourde. Jamais un nettoyage aveugle : verifie reellement que `/home` est quasi vide (< 50 Mo - le squelette par defaut, aucun utilisateur interactif reel sur ce role ou l'unique acces est root via SSH) avant de le toucher - si une vraie donnee y est trouvee, le job se contente de le signaler et n'agit pas. Sur cette VM, aurait porte `/` de 35,6 Go a plus de 53 Go des le premier boot - largement suffisant pour absorber la croissance du cache Vulnerability Detector rencontree ce jour (12 Go) sans jamais approcher le seuil watermark d'Elasticsearch.

**Corrige egalement** (`INFRA_004_HEALTH_GUARDIAN`) : l'alerte disque (>=85%) inclut desormais directement le plus gros poste de consommation (`du` cible, uniquement declenche quand l'alerte est deja active - jamais en fonctionnement normal) - le prochain incident de ce type s'identifie en un seul log, sans avoir a redemander `du -xh --max-depth=1` manuellement comme aujourd'hui.

**Limite honnete** : ce job corrige le disque APRES l'installation OS (schema de partitionnement existant, jamais modifie a la racine) - un futur choix de partitionnement plus genereux pour `/` des l'installation Oracle Linux (kickstart, ou partitionnement manuel a l'installation) resterait la solution la plus propre si un template VM est un jour prepare pour ce projet.

## 2026-09-09 (suite) - SKIP_JOBS pour les crash-tests + WAZ_037 remonte a 480s (soutenance imminente)

**Demande explicite** : soutenance d'une etudiante le lendemain - deploiement a livrer, plus le temps d'absorber les crash-tests volontaires qui coupent reseau/services a chaque passage de l'orchestrateur.

**Corrige (`vars.conf`)** : `SKIP_JOBS` etend a 7 jobs, tous des simulations de sinistre deliberees (jamais des jobs d'installation reels) : `ES_051`/`LS_029`/`KB_021`/`FB_015`/`MB_015` (kill -9 / blocage de port / coupure reseau simulee) et `WAZ_018_NET`/`WAZ_027` (coupure reseau reelle, arret brutal du manager). Le mecanisme `SKIP_JOBS` (deja utilise pour `ES_001`) marque leur condition de sortie satisfaite sans executer le script - aucun job en aval (recuperation post-sinistre) ne casse : ils se contentent de redemarrer un service deja sain (verifie sur `WAZ_028`). Reversible en un instant (retirer un `JOB_ID` de la liste) une fois la soutenance passee.

**Corrige (`WAZ_037_CONVERGENT_TEST.sh`)** : meme classe de bug que `WAZ_014`/`WAZ_020_VERIFY` le meme jour - `WAZ_035C` redemarre Logstash et confirme seulement l'unite systemd active, jamais que le pipeline a reellement fini de recharger. Preuve directe dans `logstash-plain.log` : SIGTERM a 07:40:28, mais le pipeline `wazuh-alerts` n'a commence a lire `alerts.json` qu'a 07:47:32 - 7 minutes plus tard, largement au-dela des 90s alloues. Budget remonte a `WAZ_CONVERGENT_TEST_TIMEOUT_SEC=480` (nouvelle variable `vars.conf`).

**Reporte a apres la soutenance** (demande explicite utilisateur) : jeu de bascule Wazuh Dashboard <-> Kibana avec jobs "declencheurs" qui enchainent les sous-jobs de migration NoSQL dans chaque sens, generateurs d'evenements synthetiques (100 evenements Wazuh, fichier de transactions bancaires simulees a 0,5s d'ecart, remittance/billpay), jobs de purge associes - conception et construction a faire dans une session dediee, jamais improvisee sous contrainte de delai.

## 2026-09-09 (suite) - Revirement explicite : SKIP_JOBS repasse a ES_001 seul

**Demande explicite, meme jour, apres reflexion** : "ne holder rien juste ES_001 qui fait l'update laisser les autres intact." L'extension de `SKIP_JOBS` aux 7 crash-tests (entree precedente, motivee par l'urgence d'une soutenance) est annulee - ces jobs redeviennent des executions reelles sur le prochain deploiement (nouvelle machine). Seul `ES_001` (mise a jour OS, decision anterieure et distincte) reste saute.

## 2026-09-09 (suite) - $APP_BIN/$APP_CONF/$APP_INF : indirection CLI pour le futur redeploiement sur une nouvelle machine

**Demande explicite** : pouvoir taper, depuis n'importe quel repertoire d'une session CLI Linux, `$APP_BIN/order.sh <job> <raison>` (et l'equivalent pour hold/free/confirm/history/monitor...) et obtenir directement le resultat voulu - conception explicitement deleguee ("utilisez votre jugeote et psyche INTJ + INFJ + ISTJ") apres confirmation que l'objectif exige un vrai renommage des outils, pas un simple alias vers les anciens noms.

**Renommage reel effectue (`git mv`, historique preserve)**, les 12 outils de `bin/` passent a des noms courts, un seul verbe, sans prefixe/suffixe redondant (`order_job.sh` etait deja redondant avec son propre repertoire `bin/`) :
`order_job.sh`->`order.sh`, `hold_job.sh`->`hold.sh`, `free_job.sh`->`free.sh`, `set_to_ok.sh`->`confirm.sh`, `view_history.sh`->`history.sh`, `monitoring.sh`->`monitor.sh`, `notifier.sh`->`notify.sh`, `operator_profile.sh`->`profile.sh`, `rapport_audit.sh`->`audit.sh`, `reinitialiser_mdp_elastic.sh`->`reset_es_password.sh`, `reprise_deploiement.sh`->`resume.sh`, `tableau_de_bord.py`->`dashboard.py`. Toutes les references croisees mises a jour dans le depot (35 occurrences reelles trouvees par grep avant renommage, 0 restante apres - verifie).

**Architecture choisie (3 variables, sur le modele FHS/enterprise `/opt/<produit>/bin`, `/etc/<produit>`)** :
- `APP_HOME` = racine reelle du depot (ou vivent `orchestrator.sh`, `vars.conf`, `jobs_table.csv`).
- `APP_BIN` = `bin/` (les 12 outils d'action, renommes ci-dessus).
- `APP_CONF` = `APP_HOME` lui-meme (`vars.conf`, `jobs_table.csv`, `secrets/`) - **choix deliberement conservateur** : deplacer physiquement ces fichiers dans un sous-dossier `conf/` casserait le mecanisme d'auto-localisation de `vars.conf` (`INSTALL_DIR` se deduit de l'emplacement REEL du fichier via `BASH_SOURCE`) et exigerait de corriger a la main une dizaine de points d'entree qui pointent aujourd'hui directement vers `$HERE/vars.conf` (`bin/*.sh`, `orchestrator.sh`) - risque reel juste avant un redeploiement sur une nouvelle machine, pour un gain seulement cosmetique. Ecarte consciemment, pas un oubli.
- `APP_INF` = `setup/` (installateurs ponctuels : services systemd) - dossier deja existant, aucun fichier renomme dedans.
- `jobs/` reste inchange (pas dans le perimetre de la demande - ce sont des scripts internes a l'orchestrateur, jamais invoques directement par un operateur).

**Mecanisme reel (`vars.conf` seul ne suffit pas)** : les 4 variables sont definies dans `vars.conf` (pour les scripts qui le sourcent deja), mais `vars.conf` n'est JAMAIS source par un shell de connexion SSH ordinaire - seulement par les scripts du projet eux-memes. Sans rien d'autre, `$APP_BIN` resterait invisible a l'invite de commande. Nouveau script `setup/installer_env_cli.sh` (meme precedent que `installer_service_orchestrateur.sh`, meme jour de deploiement) : ecrit `/etc/profile.d/wef-app-env.sh`, charge automatiquement par bash a CHAQUE connexion de CHAQUE utilisateur - idempotent, a relancer une seule commande apres tout deplacement/re-clonage du depot (ecrase simplement l'ancien chemin par le nouveau).

**Verifie** : les 12 `git mv` confirmes via `git status --short` (12 lignes `R`, historique preserve) ; `bash -n setup/installer_env_cli.sh` propre ; grep de controle final sur les 12 anciens noms (`.sh`/`.py`/`.md`, hors `.git`) : 0 occurrence restante. `README.md` et la structure du depot documentes avec la nouvelle commande.

**Limite honnete** : non teste en reel sur la VM (pas d'acces direct) - a verifier au prochain deploiement : `sudo setup/installer_env_cli.sh` puis nouvelle session puis `$APP_BIN/order.sh <JOB_ID> "<raison>"`.

**Verifie en reel le jour meme** : `$APP_BIN`/`$APP_HOME` confirmes fonctionnels sur une VM neuve, y compris apres une reconnexion PuTTY complete (nouvelle session, `cd $APP_BIN` et `cd $APP_HOME` operationnels immediatement) - preuve que `/etc/profile.d/wef-app-env.sh` est bien charge automatiquement a la connexion.

## 2026-09-09 (suite) - ES_017/KB_005/LS_011 : les 3 seuls jobs d'installation de paquet jamais corriges pour verifier dnf install

**Incident reel, exactement celui deja signale par une etudiante** (voir `MNT_purge_complete_reinstall.sh`, correctif du 2026-09-04) : sur une VM neuve, `ES_021` (`WEF_ES_BLD_KSTINIT`) echoue avec `sudo: /usr/share/elasticsearch/bin/elasticsearch-keystore : commande introuvable`. Log reel :
```
[ES_021] Creation du keystore Elasticsearch (utilisateur elasticsearch)...
sudo: /usr/share/elasticsearch/bin/elasticsearch-keystore : commande introuvable
[ES_021] ERREUR : 'elasticsearch-keystore create' a rendu le code 1. Sortie ci-dessus.
```
Mais `ES_017` (`WEF_ES_BLD_BININST`, installation du paquet), 4 jobs plus tot dans la meme chaine, s'etait affiche `-> OK (ES_BIN_OK)` sans reserve.

**Cause reelle, trouvee en relisant `ES_017.sh`** : `dnf install -y "$PKG_SPEC"` etait appele SANS jamais verifier son code de retour - exactement la meme classe de bug deja rencontree et corrigee ailleurs dans ce depot a plusieurs reprises (`ES_010`/`DNS_001_INSTALL` le 2026-08-19, `FB_004`/`MB_004`/`WAG_003` le 2026-08-31, `WAZ_010`/`WAZ_011`/`WAZ_012` le meme mois). Grep de controle sur tous les jobs appelant `dnf install`/`yum install` : **`ES_017.sh`, `KB_005.sh` et `LS_011.sh` etaient les 3 seuls survivants** n'ayant jamais recu ce correctif deja generalise partout ailleurs - un oubli reel, jamais un choix delibere (les 3 jobs sont structurellement identiques, meme gabarit copie/colle a l'origine).

**Corrige (les 3 fichiers, meme idiome que `FB_004.sh`)** : code de sortie de `dnf install` desormais verifie ; en cas d'echec, un second essai automatique avec `--setopt=ip_resolve=4` (cas connu : IPv6 casse sur certains reseaux/hotspots, documente depuis `WAZ_010.sh`) ; si les deux echouent, le job s'arrete immediatement avec le vrai message `dnf` visible dans son propre log - plus jamais 4 jobs plus loin, sur un symptome sans lien evident avec la vraie cause. Ajout egalement d'une verification finale `rpm -q` (le paquet est-il VRAIMENT present, independamment du code de sortie de dnf) avant de declarer le job `OK`.

**Non applique** : le contournement specifique `.build-id`/`rpm --replacefiles` de `WAZ_010.sh` (conflit de lien de debogage JVM entre wazuh-indexer et logstash) n'a pas ete reporte ici - c'est un cas particulier a cette paire de paquets precise, jamais observe ni justifie pour elasticsearch/kibana/logstash installes seuls.

**Demande explicite de l'utilisateur** : "on relance tout a zero" - repartir d'un etat completement vierge sur cette VM, pas juste reprendre apres le point d'echec. Sequence donnee separement dans la conversation (jamais executee ici, aucun acces VM direct) : `./maintenance/MNT_purge_complete_reinstall.sh` (deja code, deja corrige le 2026-09-04 pour purger ELK ET Wazuh) puis `rm -rf state logs` (efface tous les marqueurs `.ok` de l'orchestrateur, deja le chemin documente par `bin/resume.sh` pour repartir a zero) puis `./orchestrator.sh`.

**Verifie** : `bash -n` propre sur les 3 fichiers modifies.

**Limite honnete** : non teste en reel sur la VM (pas d'acces direct) - la cause racine exacte du premier echec `dnf install` (reseau/DNS/depot/GPG) n'a jamais ete confirmee par une commande reelle (`rpm -qa`, sortie brute de `dnf`) avant ce correctif ; la correction s'appuie sur le pattern d'echec deja prouve identique ailleurs dans ce meme depot (echec silencieux + symptome retarde), pas sur un diagnostic direct de cette VM precise.

## 2026-09-09 (suite) - Cause racine reelle et bien plus grave : la CA racine d'usine (factory_ca.crt) generee VIDE, jamais verifiee, jamais nettoyee par le "retour a zero"

**Incident reel, decouvert en creusant un symptome qui semblait sans rapport** : sur la VM apres le correctif ES_017/KB_005/LS_011, `git pull origin main` echoue avec `error setting certificate verify locations: CAfile: /etc/pki/tls/certs/ca-bundle.crt` - impossible de recuperer le correctif lui-meme. `update-ca-trust extract` lance a la main debloque immediatement le pull. Diagnostic demande et obtenu :
```
ls -la /etc/pki/ca-trust/source/anchors/factory_ca.crt
-rw-r--r--. 1 root root 0  9 sept. 15:14 /etc/pki/ca-trust/source/anchors/factory_ca.crt

openssl x509 -in ... -noout -dates -subject
unable to load certificate
...error:0909006C:PEM routines:get_name:no start line...
```
Le certificat racine de la PKI d'usine (`factory_ca.crt`) est **VIDE (0 octet)**, injecte tel quel dans le magasin de confiance systeme - cassant TOUT le TLS sortant de la machine (git y compris), pas seulement le TLS interne du projet.

**Cause racine reelle, remontee jusqu'au bout** : `PKI_003.sh` (`openssl genrsa`), `PKI_004.sh` (`openssl req -new -x509`), `PKI_005/006/007.sh` (cle/CSR/signature serveur) et `PKI_008.sh` (assemblage fullchain) - **exactement la meme classe de bug que ES_017/KB_005/LS_011 le meme jour**, jamais reliee jusqu'ici : leurs commandes `openssl` n'etaient jamais verifiees (code de sortie ignore), et leurs tests d'idempotence se contentaient de `[ -f fichier ]` - la PRESENCE du fichier, jamais son CONTENU. Consequence, bien plus grave que pour un simple paquet dnf : une fois `factory_ca.crt` genere vide au tout premier passage (cause exacte non confirmee - VM alors limitee a 1 vCPU, memoire sous pression, `openssl req` a tres probablement echoue en silence en laissant un fichier tronque), **aucun "retour a zero" ne pouvait jamais le corriger** : ni `rm -rf state logs` (n'efface que les marqueurs `.ok` de l'orchestrateur, jamais les fichiers reels du systeme), ni `MNT_purge_complete_reinstall.sh` (nettoie les paquets ELK/Wazuh, jamais `PKI_DIR` ni le magasin de confiance OS) - le fichier vide etait donc reconduit identique a chaque nouvelle tentative, "deja present" au sens du vieux test.

**Deuxieme defaut cumule, trouve dans `PKI_009.sh`** : `update-ca-trust` etait appele SANS argument. Preuve directe et immediate : `update-ca-trust extract` (sous-commande explicite) a resolu le probleme a l'instant ou l'operateur l'a lance a la main - la forme sans argument n'assurait pas de facon fiable la regeneration de `/etc/pki/tls/certs/ca-bundle.crt` sur cette VM.

**Corrige (PKI_003 a PKI_009, meme idiome partout)** : chaque generation `openssl` verifie desormais son code de sortie ET la validite cryptographique reelle de son propre resultat (`openssl rsa -check`, `openssl x509 -noout`, `openssl req -noout`, comptage de blocs PEM pour la fullchain) avant de declarer OK. Les tests d'idempotence ne sautent plus jamais un fichier juste parce qu'il existe : un fichier present mais invalide declenche desormais une regeneration automatique, avec un avertissement explicite - **auto-guerison reelle**, sans devoir jamais trouver et supprimer le fichier corrompu a la main. `PKI_009.sh` : `update-ca-trust` -> `update-ca-trust extract` (sous-commande explicite), plus verification de la source AVANT toute injection dans le magasin de confiance systeme (jamais plus de corruption propagee la ou elle a le plus de consequences).

**A faire sur la VM (donne separement dans la conversation, jamais execute ici)** : `git pull origin main` (deja confirme fonctionnel une fois `update-ca-trust extract` lance a la main) puis `rm -rf state logs` (une fois de plus, necessaire pour que PKI_003-011 soient rejoues et que les nouvelles verifications s'appliquent reellement - sans ca, les `.ok` du run precedent les feraient sauter) puis `./orchestrator.sh`.

**Verifie** : `bash -n` propre sur les 7 fichiers modifies (`PKI_003` a `PKI_009`).

**Limite honnete** : la cause exacte du tout premier `openssl req` silencieusement en echec (entropie, memoire, disque au moment precis du tout premier passage sur cette VM a 1 vCPU) n'est pas confirmee par une preuve directe - seule sa consequence (fichier vide) l'est. La correction protege contre TOUTES les causes possibles de ce symptome (verification du resultat, jamais de la cause), ce qui est suffisant ici, mais la cause initiale precise reste non identifiee.

## 2026-09-09 (suite) - Deploiement complet reussi (PKI a WAZ_035A, ~1h de chaine continue) + 3 correctifs supplementaires

**Contexte** : premiere execution en reel du correctif PKI_003-009 sur la meme VM (`git pull` + `rm -rf state logs` + `./orchestrator.sh`) - chaine complete PKI -> ES (61 jobs) -> LS (36 jobs) -> KB (29 jobs) -> WAZ (jusqu'a WAZ_035A) executee sans aucun echec sur pres d'une heure, preuve reelle que les correctifs PKI/ES_017/KB_005/LS_011 du jour tiennent en conditions reelles. Egalement observe et explique a l'utilisateur (sans changement de code) : `WAZ_018_NET` (crash-test reseau) n'a pas coupe la session PuTTY cette fois-ci - regle firewalld `ESTABLISHED,RELATED` deja posee par `ES_011-015` evaluee avant la regle DROP ajoutee en fin de chaine par ce job ; comportement non garanti (voir l'incident reel 2026-08-19 documente dans `installer_service_orchestrateur.sh`, ou l'inverse s'est produit).

**1) References croisees oubliees lors du renommage `bin/` (meme correctif que plus tot, perimetre incomplet)** : le grep de verification initial du renommage des 12 outils ne couvrait que `.sh`/`.py`/`.md` - jamais `jobs_table.csv` (une description de job affichait encore `bin/order_job.sh` en toutes lettres dans le log reel de l'utilisateur), ni `secrets/README_SECRETS.txt`/`vars.conf` (`notifier.sh`, `tableau_de_bord.py`). 8 occurrences reelles trouvees et corrigees, verifie par un grep sans filtre d'extension cette fois (0 restante, y compris `.git` exclu et `JOURNAL_TECHNIQUE.md` qui garde volontairement les noms historiques).

**2) `WAZ_035B_CUT_INDEXER_TO_ES` : 12 documents restants apres coupure, cause reelle trouvee (`jobs/lib/cut_migrate.sh`)** - log reel :
```
SOURCE_AVANT=174
MIGRE=174
DESTINATION_APRES=174
SOURCE_APRES_SUPPRESSION=12
ERREUR : 12 document(s) restant(s) cote source apres _delete_by_query...
```
Cause reelle, jamais un bug de comptage : `WAZ_035A_PAUSE_DEP_JOBS` (job precedent) suspend uniquement les JOBS de l'orchestrateur qui dependent de wazuh-indexer - il ne coupe JAMAIS le pipeline Logstash `WAZ_014B_ALERTS_TO_INDEXER` reellement actif, qui continue d'ecrire de vraies nouvelles alertes en direct pendant toute la migration. `_delete_by_query` fait sa propre recherche interne au moment ou il demarre : les documents arrives apres ce point de depart (mais avant sa fin) survivent, sans avoir non plus ete captes par le scroll de migration (deja termine plus tot) - donnee jamais perdue, mais le job echouait a tort sur un flux d'ingestion normal et attendu pendant la bascule.

**Corrige** : `cut_migrate_alerts` reessaie desormais la sequence migration+suppression sur le reliquat, jusqu'a 5 tentatives, jusqu'a convergence reelle vers 0 documents cote source - jamais une boucle infinie, echec explicite et honnete si le flux d'ingestion ne se tarit jamais en 5 passes. Meme fonction partagee par `WAZ_039C_CUT_ES_TO_INDEXER` (bascule inverse), donc corrige des deux cotes a la fois.

**3) Nouvel outil `bin/summary.sh`, demande explicite** : "je ne veux plus voir la liste des jobs qui se repete... je veux juste un tableau avec les URL, login et mot de passe et des scenarios de job a jouer." Lit l'etat REEL de la machine a l'appel (vars.conf, secrets/*.txt, state/es_bootstrap_password.secret, port reel de Wazuh Dashboard lu dans sa propre config) - jamais une valeur en dur, donc toujours juste meme si vars.conf est personnalise ou qu'un mot de passe n'a pas encore ete genere. Affiche : URLs+identifiants des 6 points d'acces (Wazuh Dashboard, Kibana, Elasticsearch, Wazuh Indexer, Wazuh API, tableau de bord de suivi), le mode actif (Wazuh Dashboard vs Kibana, detecte via `systemctl is-active`), et les commandes `$APP_BIN/order.sh` pretes a copier-coller pour les scenarios courants (bascule dans les deux sens, seed/purge de donnees de demo).

**Verifie** : `bash -n` propre sur `cut_migrate.sh` (wrapper bash) et sur le bloc Python embarque (`py_compile`) ; `bash -n` propre sur `bin/summary.sh`.

**A faire sur la VM (donne separement dans la conversation, jamais execute ici)** : `git pull origin main` puis relancer la chaine a partir de `WAZ_035B_CUT_INDEXER_TO_ES` (`./orchestrator.sh` reprend automatiquement, tous les jobs anterieurs restent `.ok`) ; `$APP_BIN/summary.sh` une fois le deploiement termine pour le tableau final.

## 2026-09-09 (suite) - Deploiement reel confirme : bascule Kibana<->Wazuh Dashboard complete dans les DEUX sens (WAZ_035B a WAZ_041) + WAZ_044 corrige

**Preuve reelle majeure** : sur la meme VM, apres `git stash`/`git pull`/`git stash pop` (conflit local reel sur `SKIP_JOBS` dans `vars.conf`, ecrit en direct par `WAZ_035A_PAUSE_DEP_JOBS` - fusionne proprement, aucune perte), la chaine complete de bascule s'est executee de bout en bout SANS AUCUN ECHEC : `WAZ_035B_CUT_INDEXER_TO_ES` (correctif du jour, plus aucun document residuel) -> `WAZ_035C` -> `WAZ_035D` -> `WAZ_036` -> `WAZ_037_CONVERGENT_TEST` (correctif du jour) -> `WAZ_038` -> `WAZ_039_WAZUH_TRIGGER` -> `WAZ_039A/B/C` (bascule inverse, meme fonction `cut_migrate_alerts` corrigee) -> `WAZ_039D` -> `WAZ_040_KIBANA_SILENT` -> `WAZ_041_ALERT_CANARY`. Premiere preuve reelle, en conditions completes, que le jeu de bascule Wazuh Dashboard <-> Kibana (demande initiale de l'utilisateur, deja construit avant ce jour) fonctionne integralement dans les deux sens.

**Nouvel echec reel, cause trouvee** : `WAZ_044_VD_SAFE_RETRY` (relance du module Vulnerability Detector) timeout apres 6 minutes, sans confirmation ni erreur dans le journal. Diagnostic demande et obtenu : `wazuh-manager` confirme actif et stable (`systemctl status`, 13 min sans crash), mais `tail -50 /var/ossec/logs/ossec.log` a ce stade avance de la chaine (ES+LS+KB+WAZ tous actifs simultanement) ne montre QUE du bruit debug tres dense (`wazuh-db` qui se reconnecte toutes les ~10s, `syscheckd`/`logcollector`) - aucune ligne Vulnerability* visible. Cause reelle : le job sondait une fenetre FIXE des 50 dernieres lignes toutes les 5s - sous ce volume de bruit, largement plus de 50 lignes peuvent s'ecrire entre deux sondages, poussant le message cible (demarrage OU erreur) hors de la fenetre avant d'etre vu. Jamais un vrai blocage du module, un defaut de detection.

**Corrige (`jobs/WAZ_044_VD_SAFE_RETRY.sh`)** : la fenetre de lecture n'est plus une fenetre glissante (`tail -n 50`) mais une fenetre CROISSANTE depuis le nombre de lignes du journal fige au moment precis du redemarrage (`tail -n +$((RESTART_LINE+1))`) - chaque sondage relit TOUT ce qui a ete ecrit depuis, jamais de risque de perdre un message, jamais de risque de reagir a une ancienne ligne d'un run precedent non plus. Budget remonte a `WAZ_VD_RETRY_TIMEOUT_SEC` (nouvelle variable `vars.conf`, defaut 600s/10min, meme discipline que `WAZ_CONVERGENT_TEST_TIMEOUT_SEC`/`WAZ_INDEX_VERIFY_TIMEOUT_SEC` le meme jour).

**Bruit cosmetique contenu (`orchestrator.sh`, `write_report()`)** : un message `xargs: '/dev/null': Aucun fichier ou dossier de ce type` s'affichait nu dans le terminal (sans horodatage) entre le log "Arret orchestrateur" et "Rapport ecrit" - jamais un vrai blocage (le rapport s'ecrivait quand meme correctement juste apres, confirme par le log suivant). Cause exacte non reproduite/confirmee malgre inspection du code (seul `xargs -n1 basename` a la ligne 124 est un candidat plausible par position/contenu, mais son mecanisme d'echec exact reste incertain) - le vrai defaut trouve et corrige est que le bloc `write_report()` ne redirigeait que STDOUT vers `REPORT_FILE`, jamais STDERR, qui fuyait donc integralement dans la session de l'operateur. Desormais capture dans `RUN_LOG` au lieu de polluer silencieusement le terminal - honnete : ceci contient le symptome, ne prouve pas la cause racine exacte.

**Verifie** : `bash -n` propre sur `orchestrator.sh`, `jobs/WAZ_044_VD_SAFE_RETRY.sh`, `vars.conf`.

**A faire sur la VM** : `git pull origin main` puis `./orchestrator.sh` (reprend automatiquement a `WAZ_044_VD_SAFE_RETRY`, tout le reste deja `.ok`).

**Limite honnete** : le reessai borne de `cut_migrate_alerts` suppose un flux d'ingestion qui finit par se tarir/ralentir suffisamment pour converger en 5 passes - vrai pour ce projet (flux de demo/test borne), pas garanti dans l'absolu sous un flux constamment plus rapide que le cycle migration+suppression.

## 2026-09-09 (suite) - Mise a niveau demandee : plus jamais de conflit git sur vars.conf + bits executables manquants

**Demande explicite** : "penser a mettre tout a niveau avec les bidouillages que vous me faites faire a la main" - l'utilisateur ne veut plus d'intervention manuelle recurrente entre un `git pull` et la reprise de l'orchestrateur. Audit complet de chaque action manuelle faite sur la VM ce jour, verifiee une par une :

1. **`update-ca-trust extract`** - deja automatise le meme jour dans `PKI_009.sh` (entree precedente). Confirme : plus necessaire desormais.
2. **`git stash` / `git pull` / `git stash pop`** - cause racine reelle trouvee et corrigee (voir ci-dessous). Ne devrait plus se reproduire pour CETTE raison precise.
3. **`rm -rf state logs`** - reste volontairement manuel : c'est l'action deliberee de "repartir a zero", jamais quelque chose a automatiser (deja documente par `bin/resume.sh`), pas un bug.
4. **Bits executables manquants** - trouve en audit systematique (`git ls-files -s -- '*.sh'`) : `bin/summary.sh` et `setup/installer_env_cli.sh` (nouveaux fichiers du jour), plus `jobs/ES_B001B_CPU_CHECK.sh` et `jobs/INFRA_002_RECLAIM_HOME.sh` (plus anciens, sans consequence reelle puisque l'orchestrateur invoque toujours `bash "$SCRIPT_PATH"` - jamais `./script.sh` directement - mais incoherent et piegeux si un operateur les lance a la main). Corrige (`git update-index --chmod=+x` sur les 4) - un `git pull` suffira desormais, plus de `chmod +x` a refaire a la main pour un fichier deja existant lors d'une mise a jour.

**Cause racine reelle du conflit git (point 2), trouvee dans `jobs/lib/skip_jobs_toggle.sh`** : `add_jobs_to_skip_list`/`remove_jobs_from_skip_list` (utilises par `WAZ_035A_PAUSE_DEP_JOBS`/`WAZ_039D_RESUME_DEP_JOBS` a CHAQUE bascule Kibana<->Wazuh) modifiaient directement `vars.conf` via `sed -i` - un fichier VERSIONNE dans Git. Chaque bascule laissait donc une vraie modification locale non commitee sur la VM, qui entrait en conflit avec le prochain `git pull` ("vos modifications locales... seraient ecrasees"). Cause de fond : melange entre configuration D'INTENTION (`SKIP_JOBS` pose par l'operateur, doit survivre a un `git pull`) et etat D'EXECUTION temporaire (pause du temps d'une bascule, ne devrait jamais toucher un fichier versionne).

**Corrige** : la pause runtime vit desormais dans `STATE_DIR/skip_jobs_runtime.conf` - deja gitignore comme tout `STATE_DIR` (voir `.gitignore`), jamais commite, jamais en conflit. `vars.conf` n'est plus JAMAIS modifie par un job. `job_in_skip_list()` (`lib/commun.sh`) consulte desormais les DEUX sources (`SKIP_JOBS` de `vars.conf` ET ce fichier runtime) - le comportement observable pour l'operateur (jobs sautes pendant une bascule) reste identique, seul l'emplacement de stockage change. `.gitignore` complete avec `vars.conf.bak_*` (ancien mecanisme de sauvegarde avant modification, retire - peut trainer sur une VM deja deployee avant ce correctif, sans consequence).

**Verifie** : `bash -n` propre sur `lib/commun.sh`, `jobs/lib/skip_jobs_toggle.sh`, `jobs/WAZ_035A_PAUSE_DEP_JOBS.sh`, `jobs/WAZ_039D_RESUME_DEP_JOBS.sh` ; `git ls-files -s -- '*.sh'` confirme 0 fichier `.sh` sans bit executable.

**Recommandation donnee separement a l'utilisateur (pas un changement de code)** : pour ne plus jamais avoir a "lancer l'orchestrateur et le regarder s'arreter", passer desormais par le service systemd deja construit (`setup/installer_service_orchestrateur.sh` puis `systemctl start wef-orchestrateur`) plutot que `./orchestrator.sh` en direct dans une session SSH - un echec devient consultable a son propre rythme (`systemctl status`, `journalctl -u wef-orchestrateur`, `bin/monitor.sh`) au lieu d'exiger une presence continue.

**Limite honnete** : la VM actuelle porte encore un `vars.conf.bak_*` residuel de l'ancien mecanisme (inoffensif, desormais gitignore) - a nettoyer manuellement si souhaite (`rm vars.conf.bak_*`), jamais fait automatiquement (pas notre fichier a supprimer sans consentement explicite).

## 2026-09-09 (suite) - Deploiement complet reussi (DNS_001 a ES_063, zero echec) + noms courts + tableau final auto-ecrit + jeu de remplissage visible + seuils ES configurables

**Jalon reel** : sur la meme VM, le run complet (repris a `WAZ_044_VD_SAFE_RETRY` apres le correctif precedent) est alle jusqu'a `ES_063_SNAPSHOTPOLICY` puis `=== Fin orchestrateur ===` SANS AUCUN ECHEC - premiere fois de la journee que la chaine complete (271 jobs) se termine de bout en bout sur cette VM.

**Demande explicite, plusieurs volets** : noms de scripts/services "trop longs, trop de tirets" ; plus jamais voir le defilement des `.ok` en fin de run, juste un tableau exploitable ecrit dans un fichier ; un "jeu" de remplissage visible (100 evenements, 1/s - revise depuis 0,5s) pour regarder les donnees arriver en direct dans les tableaux de bord pendant le scenario bascule+demo ; seuil de rotation et format des index Elasticsearch pilotables depuis `vars.conf`.

**1) Noms raccourcis** : `setup/installer_service_orchestrateur.sh` -> `setup/svc_orch.sh` ; `setup/installer_service_tableau_de_bord.sh` -> `setup/svc_dash.sh` (`git mv`, historique preserve) ; unite systemd `wef-orchestrateur.service` -> `wef.service` (zero tiret) ; `wef-tableau-de-bord.service` -> `wef-dash.service`. Toutes les references croisees mises a jour (`orchestrator.sh`, les 2 scripts renommes eux-memes, `docs/GUIDE_EXPLOITATION.md`, `README.md`, `bin/dashboard.py`, `jobs/LS_B025_ARMED.sh`, `setup/installer_env_cli.sh`, `vars.conf`) - verifie par grep sans filtre d'extension, 0 occurrence residuelle (hors note historique volontaire dans les 2 fichiers renommes et dans ce journal). Commande finale : `sudo setup/svc_orch.sh` puis `systemctl start wef`.

**2) Tableau de bord final auto-ecrit (`orchestrator.sh`)** : le dump brut `ls state/*.ok` en fin de run est remplace par un appel a `bin/summary.sh`, ecrit dans `state/TABLEAU_DE_BORD_FINAL.txt` ET affiche - uniquement quand le deploiement se termine SANS aucun echec (rien d'exploitable a montrer sinon). La liste exhaustive des `.ok` reste consultable dans `state/RAPPORT_EXECUTION.txt` (jamais perdue, juste plus imposee a chaque run). `bin/summary.sh` enrichi avec les 2 nouveaux scenarios de remplissage visible.

**3) Jeu de remplissage visible (`WAZ_048_SEED_INDEXER_LIVE`/`WAZ_049_SEED_ES_LIVE`, nouveaux)** : distinct de `WAZ_045A`/`WAZ_045B` (chargement de masse **instantane**, pense pour tester la migration, jamais visible a l'oeil nu) - nouvelle fonction `seed_test_alerts_live()` (`jobs/lib/test_data_tools.sh`) insere UN document a la fois (`_doc`, pas `_bulk`) avec un `_refresh` et une vraie pause `WAZ_DEMO_SEED_INTERVAL_SEC` (nouvelle variable `vars.conf`, defaut 1s) entre chaque, sur `WAZ_DEMO_SEED_COUNT` documents (defaut 100). Memes garde-fous que WAZ_045A/B : `IN_COND=WAZ_PURGE_MANUAL_GATE` (jamais dans la chaine automatique, uniquement `bin/order.sh`), meme champ `wef_test_seed: true` distinctif.

**4) Format et rotation des index Elasticsearch generiques configurables** : `ES_INDEX_NAME_PREFIX` (nouvelle variable `vars.conf`, defaut `"log"`) - une seule source de verite consommee a la fois par `ES_040.sh` (gabarit d'interception `${ES_INDEX_NAME_PREFIX}-*`) ET `LS_024.sh` (nom d'index reellement ecrit `${ES_INDEX_NAME_PREFIX}-%{+YYYY.MM.dd}`) - jamais les deux a corriger separement si l'un change. `ES_ILM_ROLLOVER_MAX_AGE`/`ES_ILM_ROLLOVER_MAX_SIZE`/`ES_ILM_WARM_MIN_AGE`/`ES_ILM_DELETE_MIN_AGE` (nouvelles variables, memes valeurs par defaut que l'ancien code en dur - `1d`/`10gb`/`3d`/`30d`) pilotent desormais `ES_037.sh` (politique ILM `factory_lifecycle`) - abaisser `ES_ILM_ROLLOVER_MAX_SIZE` a une valeur minuscule (ex: `"5kb"`) permet de VOIR le rollover se produire en direct pendant une demo, puis rejouer `ES_037` via `bin/order.sh` pour appliquer. Explicitement hors perimetre : les index Wazuh natifs (`wazuh-alerts-4.x-*`), leur format est impose par Wazuh lui-meme, jamais par ce projet.

**5) Documentation** : nouvelle section "Connexion (URLs, identifiants) et tableau de bord final" + "Scenario demo : bascule + remplissage visible" dans `docs/GUIDE_EXPLOITATION.md`, avec la sequence exacte demandee (connexion -> bascule -> remplissage visible -> observation).

**Abandonne, sur decision explicite de l'utilisateur** : la piste "historique/rapports strictement scopes a un seul deploiement" (souci reel : reutiliser la meme VM pour la soutenance de l'etudiante heriterait de tout l'historique de test d'aujourd'hui) - laissee de cote au profit des points ci-dessus, jamais implementee.

**Verifie** : `bash -n` propre sur tous les fichiers `.sh` modifies/crees (`orchestrator.sh`, `bin/summary.sh`, `setup/svc_orch.sh`, `setup/svc_dash.sh`, `setup/installer_env_cli.sh`, `ES_037.sh`, `ES_040.sh`, `LS_024.sh`, `WAZ_048/049`, `test_data_tools.sh`) ; `py_compile` propre sur le nouveau bloc Python `seed_test_alerts_live` ; `jobs_table.csv` verifie a 8 colonnes sur toutes les lignes ; grep de controle final sans filtre d'extension sur les anciens noms de service : 0 occurrence residuelle (hors note historique volontaire) ; `git ls-files -s -- '*.sh'` confirme 0 fichier sans bit executable (les 2 nouveaux jobs necessitaient un `git update-index --chmod=+x` explicite, meme limitation deja rencontree ce jour sur un depot Windows/Git Bash).

**Limite honnete** : aucun de ces changements n'a ete teste en reel sur la VM (pas d'acces direct) - notamment `seed_test_alerts_live()` (insertion document par document avec `_refresh` a chaque fois - cout reseau/CPU par document jamais mesure en conditions reelles sur cette VM deja chargee) et le rollover ILM a seuil abaisse (jamais observe en direct que la demo se deroule comme prevu).

## 2026-09-09 (suite) - Couverture $APP_* completee : APP_JOBS et APP_MNT, plus aucun dossier de scripts sans variable

**Demande explicite** : "je dois etre capable d'appeler n'importe quel script a partir d'une variable de ce genre ($APP_BIN/orchestrator.sh ce n'est qu'une illustration)". `orchestrator.sh` est deja correctement joignable via `$APP_HOME/orchestrator.sh` (sa vraie place architecturale - jamais `bin/`, reserve aux outils d'action operateur) - mais audit systematique de CHAQUE dossier de scripts du depot (`ls -d */`, comptage reel) a trouve deux trous reels : `jobs/` (275 scripts, aucune variable) et `maintenance/` (4 scripts, aucune variable).

**Corrige (`vars.conf`)** : deux nouvelles variables completant le schema existant - `APP_JOBS="${INSTALL_DIR}/jobs"`, `APP_MNT="${INSTALL_DIR}/maintenance"`. Exclusion deliberee, documentee : `jobs/lib/` et `lib/` (fonctions partagees, jamais executees seules - toujours "source"ees par un autre script) n'ont volontairement AUCUNE variable dediee, pour ne jamais laisser croire qu'on peut les lancer directement (ce qui echouerait toujours, ce sont des collections de fonctions bash, pas des points d'entree).

**Nuance honnete documentee (README, cette meme entree)** : `$APP_JOBS/*.sh` ne sont PAS concus pour un lancement direct sans contexte - chaque job commence par `source "$VARS_FILE"`, une variable normalement exportee par `orchestrator.sh`/`bin/order.sh` AVANT de les invoquer. `$APP_JOBS` sert surtout a les localiser/lire en un seul saut (`cat $APP_JOBS/<JOB>.sh`), le lancement reel passe par `bin/order.sh`. `$APP_MNT/*.sh`, a l'inverse, sont autonomes (verifie : aucun ne source `$VARS_FILE`) - directement executables via `$APP_MNT/<script>.sh`.

**Propage** : `setup/installer_env_cli.sh` exporte desormais les 6 variables (`APP_HOME`/`APP_BIN`/`APP_CONF`/`APP_INF`/`APP_JOBS`/`APP_MNT`) dans `/etc/profile.d/wef-app-env.sh`. `README.md` : tableau complet des 6 variables avec un exemple d'usage reel pour chacune, remplace l'ancienne liste prose partielle.

**Verifie** : `bash -n` propre sur `vars.conf` et `setup/installer_env_cli.sh`.

**Limite honnete** : non teste en reel sur la VM (pas d'acces direct) - a verifier au prochain `sudo setup/installer_env_cli.sh` + nouvelle session : `echo $APP_JOBS`, `echo $APP_MNT`.

## 2026-09-09 (suite) - docs/GUIDE_EXPLOITATION.md reecrit en entier : $APP_* partout, synthese systemique, remplissage confirme manuel des deux cotes

**Demande explicite, plusieurs volets** : (1) confirmer que `WAZ_048_SEED_INDEXER_LIVE`/`WAZ_049_SEED_ES_LIVE` restent strictement manuels, des deux cotes (wazuh-indexer ET Elasticsearch) ; (2) les documenter avec toutes les commandes que ca implique ; (3) TOUTE commande du guide d'exploitation doit utiliser les variables `$APP_*` - "je ne veux rien voir qui n'utilise pas les variables" ; (4) une rubrique de synthese systemique listant les 6 variables, leur contenu, ET une colonne "pourquoi" (role de chaque repertoire) ; (5) un document qui ne garde que l'essentiel - le document precedent portait des sections datant de juillet, jamais retravaillees depuis.

**Verification demandee, faite avant toute redaction (jamais suppose)** : `grep -n ",WAZ_PURGE_MANUAL_GATE$" jobs_table.csv` (chercher si cette condition est produite par un OUT_COND quelconque) -> **0 resultat**. Confirme : `WAZ_045A/045B/046/047/048/049` (les 6 jobs qui touchent aux donnees de test/demo, des deux cotes wazuh-indexer et Elasticsearch) ont tous `IN_COND=WAZ_PURGE_MANUAL_GATE` - une condition que rien ne produit jamais, donc strictement inatteignable par l'orchestrateur seul, uniquement declenchable via `bin/order.sh` (force explicite). Aucune ambiguite, verifie sur les 6 lignes.

**`docs/GUIDE_EXPLOITATION.md` reecrit integralement** (jamais un patch incrementiel - le contenu precedent melangeait plusieurs mois d'ajouts successifs, jamais retravaille en un tout coherent) :
- Nouvelle rubrique "Synthese systemique" en tete de document : tableau des 6 variables `$APP_*`, avec une colonne "Pourquoi ce repertoire existe" (role architectural de chaque dossier, pas juste son chemin).
- Etape 0 explicite : `git clone` (remplace l'ancien flux "copiez l'archive tar.gz" - jamais utilise en pratique aujourd'hui, le vrai flux reel de toute la session a ete `git clone`/`git pull`) + `setup/installer_env_cli.sh`, AVANT le premier deploiement (les variables sont donc actives des le tout premier `orchestrator.sh`).
- Toutes les commandes (deploiement, controle des jobs, scenarios demo, reglages) reecrites avec `$APP_HOME`/`$APP_BIN`/`$APP_CONF`/`$APP_INF`/`$APP_MNT` - plus aucun chemin relatif (`./bin/...`, `./orchestrator.sh`) nulle part dans le document.
- Nouvelle section "Scenario demo" avec un tableau comparant explicitement `WAZ_045A/045B` (chargement instantane, test de migration) et `WAZ_048/049` (remplissage visible, demo) plus la sequence complete (connexion -> bascule -> remplissage -> observation -> purge).
- Section "Vocabulaire operateur" (`bin/profile.sh`, alias `wenv`/`escreds`/`kburl`...) retiree deliberement : redondante avec le nouveau systeme `$APP_*`, qui couvre desormais le meme besoin sans necessiter de sourcer un fichier par session. `bin/profile.sh` lui-meme n'est pas supprime, seulement sa mise en avant dans la doc.
- Document ramene de 360 a ~215 lignes - contenu operationnel conserve integralement, reformule en tableaux plutot qu'en prose repetitive.

**Verifie** : contenu recoupe avec le code reel avant publication - `bin/notify.sh --test` (option confirmee presente), `jobs_windows/orchestrator_windows.ps1` (auto-localisation via `$MyInvocation.MyCommand.Path`, fonctionne quel que soit le repertoire d'appel), `AGENT_COMPONENTS` par defaut (`FILEBEAT,METRICBEAT,WAZUH_AGENT,HOSTNAME_RENAME`, corrige une premiere version incomplete de ce tableau avant publication), `DASHBOARD_PORT` (8088).

**Limite honnete** : non verifie en reel sur la VM (pas d'acces direct) - a confirmer au prochain passage que chaque commande du guide fonctionne telle quelle une fois `setup/installer_env_cli.sh` actif.

## 2026-09-09 (suite) - $APP_* ramene de 6 a 3 variables : maintenance/ fusionne dans setup/

**Demande explicite** : "5 repertoires c'est beaucoup pour l'exploitation, arranger vous que l'on ait 3 justes et tres optimise" (6 en realite : APP_HOME/APP_BIN/APP_CONF/APP_INF/APP_JOBS/APP_MNT). Analyse avant simplification : `APP_CONF` etait deja un pur doublon d'`APP_HOME` (meme valeur exacte, aucune fonction distincte) - suppression immediate, gain net. `APP_JOBS` (jobs/) n'apportait de valeur reelle que pour LIRE un script, jamais pour le lancer seul (chaque job attend `$VARS_FILE` deja exporte) - repli naturel sur `$APP_HOME/jobs/`. `APP_INF` (setup/, installation ponctuelle) et `APP_MNT` (maintenance/, diagnostic/purge occasionnels) couvraient deux repertoires PHYSIQUEMENT distincts pour une seule et meme famille reelle : "scripts d'admin systeme, jamais du pilotage de job quotidien" - jamais de raison reelle de les separer.

**Corrige structurellement (pas juste cache derriere moins de variables)** : `maintenance/` fusionne physiquement dans `setup/` (`git mv` sur les 4 scripts `MNT_*.sh`) - le dossier `maintenance/` disparait reellement, pas seulement sa variable. Resultat : exactement 3 variables, un role architectural distinct chacune, zero chevauchement :
- `APP_HOME` = racine (ancre de tout ce qui n'a pas sa propre variable, `jobs/` inclus)
- `APP_BIN` = `bin/` (seuls scripts qu'un operateur tape au quotidien)
- `APP_INF` = `setup/` (admin systeme : installation ponctuelle + maintenance occasionnelle, desormais regroupes au meme endroit)

**Propage partout** : `vars.conf` (definition + commentaire d'explication du choix, historique des 6 variables precedentes conserve pour memoire) ; `setup/installer_env_cli.sh` (exporte desormais 3 variables) ; `README.md` (tableau reduit a 3 lignes + colonne "Pourquoi") ; `docs/GUIDE_EXPLOITATION.md` (toutes les occurrences `$APP_CONF`/`$APP_JOBS`/`$APP_MNT` remplacees) ; toutes les references en dur a `maintenance/` corrigees en `setup/` (`orchestrator.sh`, `bin/resume.sh`, l'en-tete du script lui-meme).

**Verifie** : `bash -n` propre sur les 8 fichiers `.sh` touches (`vars.conf`, `setup/installer_env_cli.sh`, `orchestrator.sh`, `bin/resume.sh`, les 4 `MNT_*.sh` deplaces) ; grep de controle final sans filtre d'extension : 0 reference residuelle a `maintenance/` ou aux 3 variables retirees (hors notes historiques volontaires dans ce journal et dans le commentaire d'explication de `vars.conf`) ; `git ls-files -s -- '*.sh'` confirme 0 fichier sans bit executable apres le deplacement.

**Limite honnete** : non verifie en reel sur la VM (pas d'acces direct) - a confirmer au prochain `sudo setup/installer_env_cli.sh` + nouvelle session : `echo $APP_INF` doit pointer vers `setup/` et y trouver les 4 scripts `MNT_*.sh` en plus des 3 scripts d'installation.

## 2026-09-09 (suite) - Deuxieme passe de raccourcissement : env.sh, pwreset.sh, MNT_reinstall.sh, MNT_purge_hist.sh, MNT_purge_disque.sh

**Demande explicite, en deux temps** : l'utilisateur a d'abord repere que `setup/installer_env_cli.sh` restait long malgre le renommage de `svc_orch.sh`/`svc_dash.sh` (oubli reel - ce fichier avait ete cree le meme jour, apres coup, jamais inclus dans la premiere passe de raccourcissement). Puis, generalisation explicite : "partout ou les noms sont longs, reduisez".

**Perimetre delibere** : uniquement les scripts **operateur-facing** (`bin/`, `setup/`) - jamais les 275 scripts de `jobs/`. Ces derniers portent le vrai nom Control-M de l'action qu'ils executent (deja un choix assume et documente dans `README.md` : "sous le vrai nom de l'action Control-M correspondante, jamais une paraphrase francaise") et sont references par leur nom exact dans `jobs_table.csv` (colonne `SCRIPT_FILE`, 275 lignes) - les renommer serait un chantier a tres large rayon d'impact, jamais demande, et sans aucun gain d'ergonomie reel (ces fichiers ne sont JAMAIS tapes directement par un operateur, uniquement via `bin/order.sh <JOB_ID>`).

**Renommages effectues (`git mv`, historique preserve)** :
- `setup/installer_env_cli.sh` -> `setup/env.sh`
- `bin/reset_es_password.sh` -> `bin/pwreset.sh` (aligne sur l'alias deja existant `wpwreset` dans `bin/profile.sh`)
- `setup/MNT_purge_complete_reinstall.sh` -> `setup/MNT_reinstall.sh`
- `setup/MNT_purge_historique.sh` -> `setup/MNT_purge_hist.sh`
- `setup/MNT_purge_rapide_disque.sh` -> `setup/MNT_purge_disque.sh`
- `setup/MNT_diagnostic.sh` : conserve tel quel (deja court, deja clair)

Prefixe `MNT_` conserve sur les 4 scripts de maintenance : rattache au blueprint numerote d'origine (chaque script rejoue une plage `MNT_0XX` documentee dans son propre en-tete, ex. "rejoue MNT_010 a MNT_018") - un renommage complet aurait rompu cette tracabilite pour un gain de longueur marginal.

**Propage** : toutes les references croisees reelles mises a jour (`bin/profile.sh`, `bin/resume.sh`, `jobs/ES_022.sh`, `jobs/ES_027.sh`, `jobs/ES_050.sh`, `jobs/INFRA_003_DEVNULL_GUARDIAN.sh`, `jobs/lib/es_admin_curl.sh`, `jobs/PKI_004.sh`, `orchestrator.sh`, `README.md`, `docs/GUIDE_EXPLOITATION.md`, `vars.conf`, et les fichiers renommes eux-memes pour leurs propres tags de log internes, ex. `[reset_es_password]` -> `[pwreset]`, `[MNT_purge_historique]` -> `[MNT_purge_hist]`).

**Verifie** : `bash -n` propre sur les 15 fichiers `.sh` touches ; grep de controle final sans filtre d'extension sur les 5 anciens noms retires ce tour : 0 occurrence residuelle (hors note historique volontaire "ex-..." dans chaque fichier renomme lui-meme) ; `git ls-files -s -- '*.sh'` confirme 0 fichier sans bit executable.

**Limite honnete** : non verifie en reel sur la VM (pas d'acces direct) - a confirmer au prochain `git pull` + `sudo setup/env.sh` que `$APP_BIN/pwreset.sh` et `$APP_INF/MNT_reinstall.sh` fonctionnent tels quels.

## 2026-09-09 (suite) - WAZ_035B/C : cause racine reelle de l'echec residuel trouvee (ordre des jobs inverse), pas juste un budget de reessai insuffisant

**Demande explicite** : "on ne veut pas de presque, on veut la perfection" - refus categorique de considerer le reessai borne (5 passes, ajoute plus tot le meme jour) comme une solution suffisante face a un NOUVEL echec residuel reel sur une VM neuve : `SOURCE_AVANT=152, MIGRE=152, DESTINATION_APRES=152`, puis 4 passes de reliquat (35, 44, 27, 3 documents arrives successivement), et malgre tout **5 documents encore residuels** apres la 5e tentative - le flux d'ingestion en direct convergeait, mais pas assez vite pour epuiser le budget fixe.

**Cause racine reelle, trouvee en comparant les DEUX sens de bascule** (jamais suppose, verifie par lecture directe de `jobs_table.csv`) :
- `WAZ_039` (retour vers Wazuh, deja fiable a 100% sur chaque test reel de la journee) : ordre `A (demarre wazui) -> B (aiguille le pipeline vers l'indexeur) -> C (coupe ES vers l'indexeur) -> D`. Le pipeline est deja redirige AVANT que la coupure ne commence - la source (Elasticsearch) est deja GELEE, plus aucune nouvelle ecriture possible, quand `WAZ_039C` s'execute.
- `WAZ_035` (vers Kibana, celui qui echoue) : ordre `A (pause) -> B (coupe l'indexeur vers ES) -> C (aiguille le pipeline vers ES) -> D`. Exactement l'ordre INVERSE - la coupure se produit AVANT que le pipeline ne soit redirige, donc `WAZ_014B_ALERTS_TO_INDEXER` continue d'ecrire de vraies nouvelles alertes dans wazuh-indexer PENDANT toute la duree de la coupure - une cible mouvante, jamais garantie de converger dans un budget fixe de tentatives.

**Corrige a la racine (`jobs_table.csv`), pas contourne** : `WAZ_035C_REROUTE_PIPELINE_ES` et `WAZ_035B_CUT_INDEXER_TO_ES` intervertis dans la chaine de dependances (`IN_COND`/`OUT_COND`) - `WAZ_035` suit desormais EXACTEMENT le meme ordre que `WAZ_039`, deja prouve fiable : aiguillage d'abord (gele la source), coupure ensuite (cible immobile). Verifie avant modification qu'aucun autre job ne depend de `WAZ_INDEXER_DATA_CUT`/`WAZ_PIPELINE_ELK_ACTIVE` a un point precis de la chaine (grep de controle, seulement ces 4 lignes concernees) et que `WAZ_035C_REROUTE_PIPELINE_ES.sh` ne suppose rien de l'etat de la coupure (lecture complete du script : ecrit un fichier de config statique, redemarre logstash, totalement independant). Le reessai borne dans `jobs/lib/cut_migrate.sh` reste en place comme filet de securite (ne devrait plus jamais se declencher en fonctionnement normal desormais).

**Verifie** : `bash -n` propre sur `WAZ_035B_CUT_INDEXER_TO_ES.sh` ; `jobs_table.csv` toujours a 8 colonnes sur toutes les lignes ; chaine `WAZ_035` relue apres modification, confirmee structurellement identique a `WAZ_039`.

**A faire sur la VM** : `git pull origin main` puis `$APP_HOME/orchestrator.sh` (reprend automatiquement - `WAZ_035A` deja `.ok`, l'orchestrateur execute desormais `WAZ_035C` en premier puisque son nouveau `IN_COND` est deja satisfait, puis `WAZ_035B` sur une source enfin geleee). Aucun nettoyage manuel des donnees necessaire : les documents deja migres vers Elasticsearch lors de la tentative precedente seront simplement re-ecrits a l'identique (memes `_id`, `_bulk` de type "index" - jamais de doublon), et les 5 documents residuels cote indexeur seront cette fois supprimes sans reliquat.

**Limite honnete** : non verifie en reel sur la VM (pas d'acces direct) - a confirmer au prochain passage que `WAZ_035B` reussit desormais du premier coup, sans jamais declencher le reessai de secours.

## 2026-09-09 (suite) - WAZ_044 : le correctif "fenetre croissante" du jour meme etait lui-meme casse - diagnostic pousse jusqu'au bout, jamais accepte a moitie

**Demande explicite, refus categorique de l'a-peu-pres** : "on ne veut pas de presque, on veut la perfection" - suite a un nouveau timeout de `WAZ_044_VD_SAFE_RETRY` (600s, aucune confirmation trouvee), alors que le correctif "fenetre croissante" du jour meme etait censement pense pour eliminer exactement ce genre de perte de message.

**Diagnostic mene jusqu'au bout, chaque hypothese verifiee ou ecartee par une preuve reelle, jamais suppose** :
1. Hypothese "le module n'a jamais demarre" (contention reelle) : ECARTEE - `grep -i vulnerab` sur le journal reel montre `"Vulnerability scanner module started."` a 20:34:22, soit 22 secondes seulement apres le redemarrage - largement dans le budget de 600s.
2. Hypothese "le fichier a tourne/ete tronque entre la capture de la ligne de depart et la fin de l'attente" : ECARTEE - `wc -l` confirme 107315 lignes actuelles, largement au-dela de la ligne de depart notee par le job (83706), un seul fichier `ossec.log` present (aucun `.log.1`/rotation).
3. Hypothese "la ligne cible est en fait AVANT la ligne de depart" : ECARTEE - `grep -n` localise le vrai message a la ligne 105331, `sed -n '83706p'` confirme que la ligne de depart correspond bien a 20:33:57 (juste avant le demarrage du job a 20:33:59) - l'ordre est correct.
4. Test direct du mecanisme exact du job (`tail -n +83707 ossec.log | grep -q "..."`) : premiere execution rendait "1" (non trouve) - mais le terminal montrait une commande visiblement dupliquee/collee deux fois sur la meme ligne (bug d'affichage au collage, pas un vrai resultat). Retape proprement avec `grep -c` : **1** occurrence trouvee - le pipeline direct fonctionne reellement.

**Cause reelle isolee par elimination** : le job ne testait pas ce pipeline directement - il capturait d'abord `tail -n +N` dans une variable bash (`NEW_LINES="$(...)"`) avant de la re-tester via `echo "$NEW_LINES" | grep`. Ce detour, jamais present dans le test manuel qui a reussi, est la seule difference reelle entre "ce qui marche" et "ce qui echoue" - cause exacte non confirmee au niveau interne de bash (soupconne : fragilite de faire transiter des dizaines de milliers de lignes croissantes par une variable shell), mais la difference de comportement est, elle, prouvee sans ambiguite.

**Corrige (`jobs/WAZ_044_VD_SAFE_RETRY.sh`)** : suppression complete de la variable intermediaire `NEW_LINES` - le job utilise desormais exactement le meme pipeline direct `tail -n +N "$OSSEC_LOG" | grep -q "..."` que celui verifie manuellement en reel sur le journal en echec, sans jamais transiter par une variable.

**Verifie** : `bash -n` propre. Honnetete assumee : la cause exacte du comportement defaillant de la variable bash n'est PAS confirmee au niveau mecanisme interne - seule sa consequence observable (echec de detection) et le remplacement verifie (pipeline direct, teste sur les donnees reelles de l'incident) le sont. Pas de certitude inventee ou elle n'existe pas.

**A faire sur la VM** : `git pull origin main` puis `$APP_BIN/order.sh WAZ_044_VD_SAFE_RETRY "correctif pipeline direct"` (ou reprise normale via `$APP_HOME/orchestrator.sh`).

## 2026-09-09 (suite) - WAZ_044 : le rejeu "pour corriger un faux echec" redemarrait un module deja sain, videant le disque a chaque tentative

**Incident reel, consequence directe du bug de detection precedent** : l'operateur rejoue `WAZ_044_VD_SAFE_RETRY` (a la main, apres le correctif "pipeline direct") - echoue desormais sur son PROPRE controle de marge disque ("seulement 9G disponibles, minimum requis 10G"), alors que le disque affichait 16G puis 13G disponibles quelques minutes plus tot dans la meme session. Demande explicite, ton sans ambiguite : "je ne veux plus que je lance les jobs et ca s'arrete."

**Cause reelle, remontee a la racine** : le vrai journal (`ossec.log`) montrait deja `"Vulnerability scanner module started."` a 20:34:22 - le module avait REELLEMENT demarre avec succes lors du redemarrage precedent. Mais ce job-la avait echoue a le DETECTER (bug de la variable bash, corrige separement dans l'entree precedente) et avait donc rapporte un FAUX echec. L'operateur, se fiant a ce faux echec, a rejoue le job - qui, N'AYANT AUCUN CONTROLE D'IDEMPOTENCE, redemarrait `wazuh-manager` SANS CONDITION, interrompant le module en plein milieu de sa decompression de 8,5G et relancant une NOUVELLE decompression partielle a chaque tentative. Le disque s'est vide de 16G a 9G en seulement 3 cycles - jusqu'a se bloquer lui-meme sur son propre garde-fou de marge disque.

**Corrige (`jobs/WAZ_044_VD_SAFE_RETRY.sh`)** : ajout d'un controle d'idempotence EN PREMIER, avant tout redemarrage - si `wazuh-manager` est actif ET que le DERNIER evenement pertinent du module dans le journal actuel est bien un "module started" (jamais suivi d'un "Stopping" plus recent), le module est deja sain : le job sort immediatement en OK, sans jamais toucher a wazuh-manager. Meme discipline que `job_done()`/les verifications de validite ajoutees plus tot le meme jour (PKI_003-009) - jamais refaire un travail deja fait avec succes, verifie a chaque fois plutot que suppose.

**Note separee, jamais un bug** : le message `[notifier] ERREUR : SMTP_PASS_FILE introuvable` observe au meme moment est sans rapport et sans consequence - `NOTIF_ENABLED="oui"` est un reglage VOLONTAIRE (active le 2026-09-01, demande explicite anterieure du client pour de vraies alertes email) ; il manque simplement le mot de passe SMTP sur cette VM neuve (normal, `secrets/` est livre vide a chaque clone, voir `secrets/README_SECRETS.txt`) - n'affecte jamais le resultat du job lui-meme.

**Verifie** : `bash -n` propre.

**A faire sur la VM** : `git pull origin main` puis `$APP_BIN/order.sh WAZ_044_VD_SAFE_RETRY "controle idempotence"` - devrait desormais soit confirmer OK immediatement (module deja sain), soit proceder normalement si un vrai redemarrage est necessaire. Le disque (actuellement sous le seuil) devra etre verifie/nettoye separement avant tout redemarrage reel eventuel (voir `INFRA_005_DISK_HYGIENE.sh`/verification manuelle de `/var/ossec/tmp`).

**Limite honnete** : non verifie en reel sur la VM (pas d'acces direct) - le controle d'idempotence suppose que le format exact des deux lignes de journal recherchees (`wm_vulnerability_scanner_stop()`/`vulnerabilityScannerFacade.cpp:611 at start()`) reste stable entre versions de Wazuh - deja confirme present sur cette VM (version Wazuh 4.14.7 vue dans les logs), mais jamais teste sur une version differente.

## 2026-09-09 (suite) - Deploiement complet reussi, tableau final affiche - mais Wazuh Dashboard injoignable depuis un navigateur externe (ERR_CONNECTION_TIMED_OUT)

**Jalon reel** : deploiement complet de la VM neuve termine sans aucun echec (DNS_001 a ES_063), tableau de bord final ecrit et affiche automatiquement pour la premiere fois en conditions reelles - exactement le comportement demande. L'utilisateur tente ensuite de se connecter au Wazuh Dashboard depuis son navigateur (`https://192.168.50.128:443/`, URL fournie par le tableau lui-meme) : `ERR_CONNECTION_TIMED_OUT` - symptome de paquets silencieusement bloques par le pare-feu, pas d'un service a l'arret (qui aurait plutot produit un refus de connexion immediat).

**Cause racine reelle, trouvee en relisant l'historique du projet** : `KB_007.sh`/`WAZ_005.sh`/`WAZ_006.sh` documentent chacun, dans leur propre en-tete, un incident deja resolu le 2026-08-31 - la zone firewalld ciblee a l'origine ("internal"/"UI_Zone") n'etait liee a AUCUNE interface reseau reelle, rendant les regles ajoutees invisibles au trafic reel. Corrige a l'epoque pour 1514/1515 (agents, `WAZ_005`), 9200/9300 (indexer, `WAZ_006`) et 5601 (Kibana, `KB_007`) - tous recibles sur la zone "public", la seule reellement active. Mais ces memes en-tetes listent EXPLICITEMENT 443 (Dashboard) et 55000 (API) comme "ouverts par coincidence, via le post-install du paquet RPM" - une hypothese JAMAIS verifiee depuis un vrai navigateur externe, et qui vient de se reveler fausse pour 443. Angle mort reel : ces deux ports precis n'ont jamais recu leur propre job dedie, contrairement a tous les autres ports externes de ce projet.

**Corrige** : nouveau job `WAZ_006B_FW_DASHAPI` (entre `WAZ_006` et `WAZ_007` dans la chaine de dependances) - ouvre `WAZ_DASH_PORT` (443, nouvelle variable `vars.conf`) et `WAZ_API_PORT` (55000, deja existant) sur la zone `public`, meme idiome exact que `WAZ_005`/`WAZ_006`/`KB_007`. `WAZ_007` (job suivant) repointe son `IN_COND` vers la nouvelle condition `WAZ_FW_DASHAPI_OK`.

**Verifie** : `bash -n` propre ; `jobs_table.csv` toujours a 8 colonnes ; `git ls-files -s` confirme le nouveau fichier executable.

**A faire sur la VM** : cette VM a DEJA termine sa chaine (tous les jobs anterieurs a `WAZ_007` sont deja `.ok`) - l'orchestrateur ne rejouera JAMAIS ce nouveau job automatiquement (son `OUT_COND` n'est requis par rien qui ne soit pas deja satisfait en aval). Forcage manuel necessaire, une seule fois sur cette VM :
```
git pull origin main
$APP_BIN/order.sh WAZ_006B_FW_DASHAPI "ouverture port dashboard manquant"
```
Sur toute future VM neuve, ce job s'executera automatiquement dans la chaine normale, sans intervention.

**Limite honnete** : le meme risque (port cru "ouvert par coincidence", jamais verifie depuis l'exterieur) pourrait exister ailleurs dans ce projet sur des ports non encore testes depuis un vrai navigateur/client externe - seul 443 a ete reellement confirme casse aujourd'hui ; 55000 est corrige par prudence/cohesion (meme hypothese non verifiee dans le meme historique), jamais reellement teste depuis l'exterieur a ce jour.

## 2026-09-09 (suite) - Deploiement complet sur VM neuve, la chaine a tourne jusqu'a WAZ_022 (validation reelle de WAZ_006B_FW_DASHAPI) - un dernier echec, cause reelle trouvee sans deviner

**Jalon reel majeur** : premier deploiement complet sur une VM authentiquement neuve depuis tous les correctifs du jour (PKI vide, ES_017/KB_005/LS_011, WAZ_035 ordre, WAZ_044, pare-feu 443/55000...). La chaine a tourne de `INFRA_002` a `WAZ_021_RECOVER` SANS AUCUN ECHEC - `WAZ_006B_FW_DASHAPI` (ajoute quelques heures plus tot le meme jour) s'est execute automatiquement dans la chaine normale et a reussi du premier coup, confirmant en conditions reelles que la correction du pare-feu tient sur une VM veritablement neuve.

**Nouvel echec reel** : `WAZ_022` (generation du token API Wazuh) - "Le defaut 'wazuh' ne fonctionne pas contre cette instance". Demande explicite de l'operateur, fatigue exprimee sans ambiguite : diagnostic mene par Claude seul, UNE seule commande demandee a l'operateur (jamais une serie), reponse traitee immediatement.

**Diagnostic** : `curl -u wazuh:wazuh -k -X POST https://127.0.0.1:55000/security/user/authenticate` lance manuellement par l'operateur quelques minutes apres l'echec -> vrai jeton JWT retourne (`{"data": {"token": "..."}, "error": 0}`). Le mot de passe par defaut EST correct - le job avait tort de rapporter un echec d'authentification.

**Cause reelle trouvee par lecture du code (`jobs/WAZ_022.sh`) et correlation des horodatages, jamais supposee** : `WAZ_022` a tourne a 22:22:14, soit UNE SECONDE apres la fin de `WAZ_021_RECOVER` (retablissement du reseau coupe par le crash-test `WAZ_018_NET`). La fonction `_waz022_auth_reussie()` ne faisait qu'UN SEUL essai curl, sans retry, sans marge. Meme famille de bug deja rencontree et corrigee plusieurs fois ce jour (`WAZ_014`/`WAZ_020_VERIFY`/`WAZ_037`) : un composant qui vient de subir une perturbation reseau peut avoir besoin de quelques secondes de plus pour que SON PROPRE sous-systeme (ici l'API `wazuh-apid`) se stabilise, meme si le service parent est deja considere "actif" ailleurs dans la chaine.

**Corrige (`jobs/WAZ_022.sh`)** : `_waz022_auth_reussie()` reessaie desormais jusqu'a 6 fois (5s d'ecart) avant de conclure a un echec - jamais un mot de passe different tente, uniquement une patience reelle. S'applique aux deux appels (tentative du defaut ET authentification avec le mot de passe reel deja connu).

**Verifie** : `bash -n` propre.

**A faire sur la VM** : `git pull origin main` puis `$APP_BIN/order.sh WAZ_022 "correctif reessai"` (ou reprise normale via `$APP_HOME/orchestrator.sh`).

**Limite honnete** : non verifie en reel sur la VM (pas d'acces direct) - le reessai borne (30s) suppose que l'API se stabilise dans cette fenetre ; jamais mesure precisement combien de temps reel il lui faut apres une coupure reseau de ce type.

## 2026-09-09 (suite) - Audit de conformite AGENT_HOST (VM2) : ROLE-awareness manquante dans bin/summary.sh, verifications dnf/pare-feu deja saines partout ailleurs

**Demande explicite** : "regarder aussi ceux-la [les jobs AGENT_HOST] si c'est conforme avec l'architecture de ELK_HOST au niveau de l'appel des commandes, le nommage, le dossier exploitation et etc - bref tout tout et tout." Audit systematique des 47 jobs `AGENT_HOST` (`FB_*`, `MB_*`, `WAG_*`, `DIST_001`, `INFRA_002`/`INFRA_006`) contre chaque classe de bug corrigee aujourd'hui sur `ELK_HOST`.

**Verifie sain, rien a corriger** :
- Aucune reference residuelle aux anciens noms `bin/`/`setup/` (grep sans filtre d'extension, meme discipline que les audits precedents du jour).
- Zero regle `firewall-cmd` dans les jobs agents - coherent : Filebeat/Metricbeat/l'agent Wazuh sont des clients purement sortants vers `ELK_HOST` (5044/1514/1515), jamais des serveurs ecoutant en entree - le bug "zone jamais liee a l'interface reelle" (ES/KB/WAZ_005/006 le meme jour) ne peut structurellement pas se produire ici.
- `FB_004.sh`/`MB_004.sh`/`WAG_003.sh` avaient deja recu, avant meme aujourd'hui, le correctif "verification reelle de dnf install" (retry IPv4 + `rpm -q`) - deja dans la bonne famille de code, rien a refaire.
- `docs/GUIDE_EXPLOITATION.md` (etape 0, section deploiement) deja generique aux deux roles depuis la reecriture du jour - `$APP_HOME/orchestrator.sh` fonctionne identiquement sur VM1 et VM2.
- `jobs_table.csv` : chaine `AGENT_HOST` verifiee structurellement saine des le premier audit du jour (simulation de resolution : 3 passes, 0 job bloque) - `INFRA_006_AGENT_RESOURCE_CHECK` bien le point d'entree unique (`IN_COND=NONE`), `FB_001`/`INFRA_002`/`WAG_001` en dependent tous les trois.

**Corrige, 3 ecarts reels trouves** :
1. **`bin/summary.sh` n'etait pas conscient du `ROLE`** (contrairement a `bin/monitor.sh`, deja filtre par role) - lance sur un `AGENT_HOST`, il aurait affiche des URLs/mots de passe Elasticsearch/Kibana/Wazuh Dashboard totalement absents de cette machine (aucun de ces services n'y tourne). Corrige : branche dediee `ROLE=AGENT_HOST` - affiche `AGENT_NAME`, les composants actifs, la machine `ELK_HOST` cible, et l'etat systemd reel de chaque service actif (filebeat/metricbeat/wazuh-agent) - jamais de tableau URLs/mots de passe hors sujet.
2. **`MB_016.sh`** (generation de charge stress-ng) : `dnf install` jamais verifie - meme classe que `ES_017`/`KB_005`/`LS_011`, impact reel moindre ici (la commande `stress-ng` suivante aurait de toute facon echoue bruyamment, jamais un echec masque), corrige par coherence.
3. **`docs/GUIDE_EXPLOITATION.md`** : le paragraphe RAM/disque ne mentionnait que `ES_B001_RAM_CHECK` (ELK_HOST) - complete avec `INFRA_006_AGENT_RESOURCE_CHECK` (AGENT_HOST) et ses 3 variables de seuil dediees.

**Verifie** : `bash -n` propre sur `bin/summary.sh` et `jobs/MB_016.sh`.

**Limite honnete, deja documentee dans le code lui-meme avant aujourd'hui** : `INFRA_006_AGENT_RESOURCE_CHECK.sh` porte sa propre mise en garde depuis sa creation - "encore jamais teste en conditions reelles sur une vraie VM2 - a verifier des le premier lancement reel". Aucun deploiement `AGENT_HOST` reel n'a encore eu lieu a ce jour (tous les tests du jour portaient sur `ELK_HOST` uniquement) - cet audit est structurel/statique, jamais un test en conditions reelles.

## 2026-09-09 (suite) - Parite Windows : variables d'exploitation `$env:APP_HOME`/`$env:APP_BIN` et tableau de bord final, comme sur ELK_HOST/AGENT_HOST

**Demande explicite** : "je veux que de la meme maniere l'exploitation des choses ... sur ELK_HOST soit pareil sur tous les postes clients de AGENT_HOST ... je veux appeler les commandes avec les variables, je veux qu'a la fin il y ait un tableau systemique qui brosse les choses comme sur ELK ... pour les postes windows faites pareillement." Le cote Linux `AGENT_HOST` avait deja ete audite (entree precedente) et etait deja conforme (meme depot, memes `bin/`, meme `setup/env.sh`). Reste `jobs_windows/` (kit agent Windows) : inspecte avant toute modification, comme convenu ("je ne veux pas deviner") - `orchestrator_windows.ps1`, `vars.ps1`, `jobs_table_windows.csv`, et deux scripts de jobs lus en detail (`WAW_001.ps1`, `FBW_004.ps1`).

**Constat reel (lecture de code, rien suppose)** : aucune variable d'environnement persistante n'existait cote Windows (chaque script se localise lui-meme via `$MyInvocation.MyCommand.Path`, ce qui fonctionne pour les jobs entre eux mais n'aide pas un operateur a taper une commande depuis un autre repertoire) ; aucun outil `bin\*` (equivalent `summary.sh`/`monitor.sh`) n'existait ; l'orchestrateur ecrivait deja `state\RAPPORT_EXECUTION.txt` (liste succes/echec/jamais-atteint) mais rien d'equivalent au tableau `TABLEAU_DE_BORD_FINAL.txt` (etat des services, scenarios prets a l'emploi) genere cote Linux uniquement si le run n'a subi aucun echec.

**Ajoute** :
- `jobs_windows/env.ps1` (nouveau) - equivalent Windows de `setup/env.sh` : ecrit 2 variables d'environnement **Machine** (memes noms que cote Linux, `APP_HOME`/`APP_BIN` - aucune collision possible, jamais la meme machine), a lancer une fois par machine en PowerShell Administrateur, puis nouvelle session pour qu'elles soient actives (meme regle que `/etc/profile.d` cote Linux). Volontairement PAS de troisieme variable type `APP_INF` : rien a y regrouper cote Windows (pas de notion de service/tache planifiee installee separement de la chaine de jobs elle-meme).
- `jobs_windows/bin/summary.ps1` (nouveau) - tableau de bord, calque sur la branche `ROLE=AGENT_HOST` de `bin/summary.sh` (Linux) : identite de l'agent, composants actifs, machine `ELK_HOST` cible, etat reel de chaque service Windows actif (`Get-Service` sur `WazuhSvc`/`filebeat`/`metricbeat`, uniquement les composants actives), scenarios utiles. Aucune URL/mot de passe (services absents de cette machine, comme cote Linux `AGENT_HOST`).
- `jobs_windows/bin/monitor.ps1` (nouveau) - etat des jobs (fait / en attente de quelle dependance), filtre par `$EnabledComponents`.
- `jobs_windows/orchestrator_windows.ps1` - en fin de run, si aucun job n'a echoue (`$Script:FailedJobId` vide, meme garde-fou que cote Linux), appelle desormais `bin\summary.ps1` et ecrit le resultat dans `state\TABLEAU_DE_BORD_FINAL.txt` en plus du `RAPPORT_EXECUTION.txt` existant.
- `docs/GUIDE_EXPLOITATION.md` - section Windows completee : activation de `env.ps1`, toutes les commandes via `$env:APP_HOME`/`$env:APP_BIN`, mention du tableau automatique et de `bin\monitor.ps1`.

**Verifie** : les 4 fichiers `.ps1` (nouveaux + modifie) parses sans erreur via `[System.Management.Automation.Language.Parser]::ParseFile` (equivalent `bash -n` pour PowerShell, verifie ici car aucun `pwsh`/`powershell.exe` d'execution reelle Windows-agent n'est disponible depuis cet environnement pour un test bout-en-bout).

**Limite honnete, assumee explicitement dans le code** (`bin/monitor.ps1`) : contrairement au cote Linux, ce kit Windows ne pose aujourd'hui que des marqueurs `*.ok` (job termine) - aucun marqueur "en cours" (`*.running`), aucun etat "gele" (HELD/Free), aucun historique dure par job (`JOBS_HISTORY.csv`). Ces fonctionnalites n'ont jamais existe dans `orchestrator_windows.ps1` avant aujourd'hui et n'ont pas ete demandees explicitement pour Windows - non ajoutees ici pour rester proportionne a la demande reelle ("variables" + "tableau final"), plutot que d'inventer une parite complete non sollicitee. Egalement jamais teste en conditions reelles sur une vraie machine Windows a ce jour (aucun deploiement Windows reel encore effectue) - a verifier des le premier lancement reel, comme deja note pour `INFRA_006_AGENT_RESOURCE_CHECK` cote Linux.

## 2026-09-09 (suite) - Premier lancement reel de `jobs_windows/env.ps1` : echec reel (droits registre) masque par un rapport de succes trompeur

**Contexte** : premier test reel du kit Windows (entree precedente), sur une VM agent Windows fraichement clonee (`git clone` + `cd WEF\jobs_windows` + `.\env.ps1`), PowerShell **non-Administrateur**.

**Echec reel observe** : `[Environment]::SetEnvironmentVariable("APP_HOME", ..., "Machine")` a leve `SecurityException` ("Acces au registre demande non autorise") - la portee `Machine` ecrit dans `HKLM`, reserve a une session elevee. Meme echec pour `APP_BIN`. **Mais le script a quand meme affiche "Variables ecrites (portee Machine)."** - aucune des deux exceptions n'a ete interceptee, PowerShell a simplement poursuivi a l'instruction suivante (comportement par defaut d'une exception levee par un appel de methode .NET hors `try/catch` : erreur terminale pour CETTE instruction seulement, pas pour le script). Un rapport de succes non verifie, exactement la classe d'erreur que ce projet a deja corrigee plusieurs fois cote Linux (PKI_003-009, dnf install ES_017/KB_005/LS_011/MB_016) : verifier l'etat REEL, jamais seulement l'absence de crash visible.

**Cause racine, pas seulement contournee** : rien dans la conception de `env.ps1` ne justifiait la portee `Machine` - ces 2 variables ne sont lues par aucun service, uniquement par l'operateur humain dans ses propres commandes. Exiger une elevation Administrateur pour un simple confort operateur etait une contrainte non necessaire, source de cet echec reel des le premier essai.

**Corrige (`jobs_windows/env.ps1`)** :
1. Portee changee de `Machine` (HKLM, admin requis) a `User` (HKCU, jamais de droits speciaux) - persiste tout autant pour les commandes de cet operateur, plus besoin d'elevation.
2. Chaque ecriture est desormais suivie d'une relecture reelle (`GetEnvironmentVariable`) avant d'annoncer un succes - un `SecurityException` (ou toute autre cause d'echec silencieux) fait desormais echouer le script visiblement (`exit 1`, message rouge), jamais un succes suppose.
3. `docs/GUIDE_EXPLOITATION.md` : etape `env.ps1` ne demande plus PowerShell administrateur (uniquement le lancement de `orchestrator_windows.ps1` lui-meme le reste, pour l'installation reelle des services Wazuh/Filebeat/Metricbeat).

**Verifie** : parse PowerShell propre (`ParseFile`, aucune erreur).

**A faire sur la VM Windows** : `git pull` (ou re-cloner), puis relancer `.\env.ps1` en PowerShell normal (non-admin) depuis `WEF\jobs_windows`.

**Limite honnete** : non re-teste en reel sur la VM au moment de ce correctif (correctif ecrit a partir du message d'erreur reel colle par l'operateur, jamais devine) - a confirmer au prochain lancement reel.

**Confirme ensuite en reel** : `env.ps1` corrige relance avec succes (portee User), variables `$env:APP_HOME`/`$env:APP_BIN` bien actives dans une nouvelle session (verifie par l'operateur avec `echo $env:APP_HOME`/`echo $env:APP_BIN`, valeurs correctes retournees).

## 2026-09-10 - Deuxieme echec reel : `$env:APP_HOME\orchestrator_windows.ps1` - erreur de syntaxe PowerShell dans ma propre documentation

**Echec reel observe** : `$env:APP_HOME\orchestrator_windows.ps1` tape tel quel -> `Jeton inattendu « \orchestrator_windows.ps1 »`. Erreur de conception dans les instructions donnees (`docs/GUIDE_EXPLOITATION.md` et les messages `Write-Host` de `bin/summary.ps1`/`bin/monitor.ps1`), jamais testee en reel avant ce jour faute d'environnement Windows disponible pour executer une vraie ligne de commande PowerShell (seul le parsing syntaxique des fichiers `.ps1` avait ete verifie, pas la syntaxe d'invocation suggeree en dehors d'un fichier).

**Cause reelle** : en debut de ligne, PowerShell parse `$env:APP_HOME\...` en **mode expression**, pas en mode commande. `$env:APP_HOME` s'evalue en chaine, puis `\orchestrator_windows.ps1` n'est ni un operateur ni la suite valide d'une expression - d'ou le jeton inattendu. Pour invoquer un script dont le chemin vient d'une variable/expression, PowerShell exige l'operateur d'appel `&` avec la chaine entre guillemets : `& "$env:APP_HOME\orchestrator_windows.ps1"`.

**Corrige** :
- `docs/GUIDE_EXPLOITATION.md` : les 3 commandes Windows (`orchestrator_windows.ps1`, `bin/summary.ps1`, `bin/monitor.ps1`) reecrites avec `& "..."`, plus une phrase expliquant pourquoi (pour que l'operateur comprenne l'erreur s'il la retape a la main ailleurs).
- `jobs_windows/bin/summary.ps1` : commentaire d'usage et les 2 lignes `Write-Host` suggerant des commandes a l'operateur, memes corrections.
- `jobs_windows/bin/monitor.ps1` : commentaire d'usage, meme correction.

**Verifie** : parse PowerShell propre sur les 2 fichiers modifies.

**Limite honnete** : toujours aucun acces a une vraie VM Windows depuis cet environnement - chaque commande suggeree n'est confirmee correcte qu'apres que l'operateur l'ait reellement tapee et collee le resultat, jamais avant. Prochaine etape reelle a confirmer : `& "$env:APP_HOME\orchestrator_windows.ps1"` en PowerShell administrateur.

## 2026-09-10 (suite) - Deploiement complet ELK_HOST sur VM neuve : ZERO echec de bout en bout, tableau de bord final confirme en conditions reelles

**Jalon reel majeur** : premiere execution complete de `INFRA_002_RECLAIM_HOME` (01:13:59) a `ES_063_SNAPSHOTPOLICY` (02:10:38) sur une VM authentiquement neuve (`git clone` frais, HEAD au moment du clone deja sur le commit du correctif `WAZ_022` - voir plus bas), **sans un seul echec**, sur toute la chaine : PKI (11 jobs), Elasticsearch (63 jobs, snapshots S3 inclus), Logstash (36 jobs, crash-tests reseau/PID/DLQ inclus), Kibana (29 jobs), Wazuh (indexeur + manager + dashboard, ~60 jobs, crash-tests inclus), les deux bascules Kibana<->Wazuh Dashboard dans les deux sens avec preuve reelle de convergence (`WAZ_037_CONVERGENT_TEST` : alerte reelle injectee puis retrouvee dans Elasticsearch), DNS interne (4 jobs), snapshots S3 OVH (2 jobs).

**Confirmations reelles precises, closant plusieurs limites honnetes notees precedemment comme "non re-teste"** :
- `WAZ_022` (correctif du 2026-09-09, 6 essais/5s) : reussi en **2 secondes** (`02:02:00` -> `02:02:02`), premier essai, aucun retry necessaire cette fois - le correctif tient sans meme avoir besoin de sa marge complete.
- `WAZ_006B_FW_DASHAPI` (ouverture pare-feu 443/55000, ajoutee le 2026-09-09) : de nouveau reussie automatiquement dans la chaine normale.
- `WAZ_035`/`WAZ_039` (bascule Kibana<->Wazuh Dashboard, ordre reroute-avant-cut corrige le 2026-09-09) : les deux sens rejoues integralement avec succes, preuve reelle de convergence des deux cotes.
- `bin/summary.sh` -> `state/TABLEAU_DE_BORD_FINAL.txt` : genere et affiche automatiquement en fin de run (le run n'a subi aucun echec), avec les vraies URLs/utilisateurs/mots de passe reels de chaque service - fonctionne exactement comme concu, en conditions reelles, pour la premiere fois.

**Note annexe verifiee dans ce meme log** : le clone utilise pour ce run partait deja du commit `a0f8983` (celui du correctif `WAZ_022`) au moment du `git clone` - confirmant qu'un clone frais aujourd'hui inclut deja tous les correctifs `ELK_HOST` du 2026-09-09, sans action supplementaire necessaire.

**Rien a corriger ici** - entree purement de confirmation, a la demande explicite de closer les limites honnetes en suspens des que des preuves reelles existent.

## 2026-09-10 (suite) - Demo enrichie (10 variantes Wazuh + application metier simulee AnkrrWEF) - developpee sur une BRANCHE, jamais sur main

**Contexte** : pendant que l'etudiante terminait son installation `ELK_HOST` (voir entrees precedentes du jour), l'utilisateur a demande explicitement de ne RIEN toucher a `main` pour ne pas risquer son `git pull` en cours, tout en voulant faire evoluer le jeu de demo (bascule + remplissage). Reponse apportee : tout ce chantier est fait sur une branche Git separee (`demo-donnees-realistes`), jamais fusionnee sur `main` sans validation explicite - `git pull origin main` reste strictement identique pour quiconque tant que la fusion n'a pas eu lieu.

**Demande 1 - la bascule Kibana<->Wazuh Dashboard** : l'utilisateur pensait qu'un bug empechait le fonctionnement voulu (Wazuh Dashboard/Indexer inactifs pendant le mode Kibana, actifs uniquement au retour). Verification du code existant (`jobs_table.csv`, jobs `WAZ_035D_STOP_WAZUI`/`WAZ_039A_START_WAZUI`) : **le mecanisme fait deja exactement ca** - rien a corriger. Le message "deja execute" de `bin/order.sh` venait du fait que les deux triggers avaient deja tourne automatiquement PENDANT le deploiement (preuve de convergence integree). Reponse : rejouer la bascule pour une demo est une simple suppression de marqueur d'etat local (`state/WAZ_KIBANA_TRIGGERED.ok`/`WAZ_WAZUH_TRIGGERED.ok`) - AUCUNE action Git, documente desormais dans `docs/GUIDE_EXPLOITATION.md`.

**Demande 2 - donnees de demo plus realistes** :
1. **Cote Wazuh (wazuh-indexer/Elasticsearch, alertes)** : le jeu de regles synthetiques (`jobs/lib/test_data_tools.sh`, `seed_test_alerts`/`seed_test_alerts_live`) etoffe de 4 a 10 variantes plausibles (auth PAM ouverture/fermeture, sshd utilisateur inexistant, sshd brute force, canari WEF, attaques web SQLi/XSS, integrite syscheck, rootcheck, vulnerabilite CVE) - meme format deja verifie contre le modele officiel `wazuh-alerts-4.x-*` (`WAZ_014C_ALERTS_TEMPLATE`). LIMITE HONNETE documentee directement dans le code : ceci peuple uniquement `wazuh-alerts-4.x-*` - "Wazuh Monitoring"/"Wazuh Statistics" sont des index distincts, alimentes automatiquement par le manager/l'API Wazuh eux-memes, jamais par ce mecanisme (terme employe par l'utilisateur mais aucun format verifie pour ces deux-la - non simule au hasard).
2. **Cote Elasticsearch/Kibana (application metier simulee)** : nouvelle fonction `seed_ankrrwef_transactions_live()` (meme fichier) - genere des evenements de transaction (transfert d'argent, microservices `remittance`/`billpay`/`account-transfer`/`fx-exchange` sur `glassfish-01`/`tomcat-02`, statuts SUCCESS/FAILED/PENDING ponderes realiste) dans un nouvel index fixe `AnkrrWEF` - jamais melange avec les fausses alertes Wazuh (format de document completement different, toujours `wef_test_seed: true`).

**Nouveaux jobs (manuels uniquement, meme `IN_COND=WAZ_PURGE_MANUAL_GATE` jamais satisfaite ailleurs - verifie par script apres ajout : 8 jobs derriere ce gate, toujours 0 doublon JOB_ID/OUT_COND, tous les `SCRIPT_FILE` resolvent)** :
- `jobs/WAZ_049B_SEED_ANKRRWEF_LIVE.sh` (`WAZ_049B_SEED_ANKRRWEF_LIVE`, `jobs_table.csv`).
- `jobs/WAZ_049C_PURGE_ANKRRWEF.sh` (`WAZ_049C_PURGE_ANKRRWEF`, `jobs_table.csv`) - meme mecanique que `WAZ_046`/`WAZ_047` (`purge_index_pattern`, deja generique).

**Verifie** : `bash -n` propre sur les 2 nouveaux jobs + `jobs/lib/test_data_tools.sh` ; les 4 blocs Python embarques (dont le nouveau) compiles sans erreur (`compile()`) ; bit executable Git corrige (`git update-index --chmod=+x`, meme gotcha Windows/Git-Bash que d'habitude) ; `jobs_table.csv` toujours 8 colonnes, 0 doublon, gate manuel toujours inatteignable automatiquement, tous les scripts references existent reellement sur le disque.

**Limite honnete** : jamais teste contre un vrai wazuh-indexer/Elasticsearch (pas d'acces VM) - la logique d'insertion `_doc`+`_refresh` est identique a `seed_test_alerts_live`, deja validee en reel le 2026-09-09, mais le format de document `AnkrrWEF` lui-meme (nouveau) n'a pas encore ete confirme par une vraie insertion. Reste sur la branche `demo-donnees-realistes` - fusion sur `main` seulement apres validation explicite de l'utilisateur ET confirmation que l'installation de l'etudiante est terminee.

## 2026-09-13 - Premier deploiement AGENT_HOST reel (VM2, 192.168.50.130) : VM reellement sous-dimensionnee, seuils ajustes en connaissance de cause + audit de conformite avant la suite

**Contexte** : premier vrai lancement de `orchestrator.sh` en `ROLE=AGENT_HOST` sur une VM authentiquement neuve (192.168.50.130) - `INFRA_006_AGENT_RESOURCE_CHECK` n'avait jamais tourne en conditions reelles jusqu'ici (mise en garde portee par son propre code depuis sa creation le 2026-08-31).

**Resultat reel** : le job a fonctionne exactement comme concu - il a detecte une machine reellement sous les seuils (1 vCPU/1 Go RAM/13 Go disque, contre 1/2/15 requis) et a arrete l'orchestrateur immediatement, avant toute installation. Rien a corriger dans `INFRA_006_AGENT_RESOURCE_CHECK.sh` lui-meme - le controle de securite a rempli son role.

**Decision operateur, explicite** : plutot que redimensionner la VM, abaisser les seuils pour cette machine reelle (proposee comme alternative, choix assume). Fait en 2 temps sur la VM (`sed` sur `vars.conf`), avec un rebond reel entre les deux : `MIN_DISK_GB_REQUIRED_AGENT` fixe d'abord a 13 (valeur mesuree), le job a immediatement re-echoue avec `12 Go` detectes une minute plus tard - **diagnostique avant d'ajuster encore** : `journalctl --disk-usage` (8 Mo) et `du -sh /var/log/*` (quelques Mo au total) confirment qu'il n'y a AUCUNE fuite disque reelle - juste l'arrondi de `df --output=avail -BG` sur un petit disque de 17 Go total (~12,4-12,9 Go reels, arrondis tantot 12 tantot 13). Seuil final pose UN CRAN SOUS la valeur mesuree (10 Go), pas pile dessus, pour absorber cette fluctuation d'arrondi.

**Corrige dans le depot (`vars.conf`)**, a la demande explicite de ne plus retomber sur ce meme mur lors d'un prochain deploiement neuf : `MIN_RAM_GB_REQUIRED_AGENT` 2->1, `MIN_DISK_GB_REQUIRED_AGENT` 15->10. LIMITE HONNETE assumee dans le commentaire du fichier : ceci reflete une VM de demo/lab reelle, pas une recommandation de dimensionnement de production - une vraie machine AGENT_HOST en production devrait rester dimensionnee selon les besoins reels de Filebeat/Metricbeat/l'agent Wazuh, ce garde-fou abaisse protege moins qu'avant.

**Audit de conformite demande explicitement ("reviser tous les jobs pour qu'un prochain deploiement neuf ne rencontre aucune erreur")** - fait par comparaison directe avec les classes de bugs deja trouvees cote `ELK_HOST`, AVANT que `AGENT_HOST` n'ait fini son tout premier vrai deploiement :
- **`dnf install` non verifie** (classe ES_017/KB_005/LS_011) : deja corrige partout cote AGENT_HOST (`FB_004`/`MB_004`/`WAG_003`/`MB_016`) depuis les audits precedents - reconfirme, rien a refaire.
- **Verification de service en un seul essai apres (re)demarrage** (classe WAZ_014/WAZ_020_VERIFY/WAZ_022/WAZ_037) : `FB_014`/`MB_014` avaient deja appris cette lecon (boucle 60x5s). **Trouve reellement en defaut par comparaison directe : `WAG_005`** (demarrage wazuh-agent) ne verifiait qu'UNE FOIS, apres un `sleep 3` fixe - incoherent avec le reste du meme fichier `jobs_table.csv`, risque reel accru sur une VM a 1 Go RAM comme celle en cours de deploiement. Corrige : boucle de reessai bornee (60x2s = 120s), diagnostic `journalctl` en cas d'echec reel, meme idiome que `FB_014`/`MB_014`.
- **Anciennes references `bin/`/`setup/`** : reconfirme absentes (grep sans filtre d'extension).
- Autres candidats verifies sans anomalie : `FB_018`/`MB_017` (verifications volontairement non bloquantes, `|| true`, ne peuvent pas produire de faux echec) ; `FB_019`/`MB_018` (retrait de regle iptables, rien a verifier en direct) ; `FB_023`/`MB_022` (controle final `is-active` en un seul essai, mais aucun redemarrage de service ne precede ce controle depuis `FB_014`/`MB_014` - pas le meme risque qu'un controle juste apres perturbation) ; `WAG_001` (ping unique vers le manager, mais AVANT toute perturbation, jamais signale en defaut sur les deploiements precedents - laisse tel quel, pas de preuve reelle justifiant un changement).

**Verifie** : `bash -n` propre sur les 46 jobs `FB_*`/`MB_*`/`WAG_*` et sur `vars.conf`.

**Limite honnete, dite clairement a l'operateur** : cet audit reste statique - la methode qui a fait ses preuves sur `ELK_HOST` (plusieurs bugs reels trouves uniquement par des deploiements reels successifs, jamais par la seule relecture de code) s'applique de la meme facon ici. `WAG_005` est corrige par anticipation, pas parce qu'il a deja echoue en reel - il reste possible que d'autres bugs, invisibles a la lecture, n'apparaissent qu'au prochain vrai passage de la chaine sur cette VM. A confirmer par la suite du deploiement en cours.

## 2026-09-13 (suite) - `DIST_001` bloque en reel (identifiants SSH absents) : distribution de la CA repensee de fond en comble, sans plus aucun identifiant

**Echec reel** : sur la VM2 en cours de deploiement, `DIST_001` (copie de `factory_ca.crt` depuis VM1) a echoue - ni `FACTORY_SSH_KEY` ni `FACTORY_SSH_PASSWORD_FILE` renseignes. Demande explicite et sans ambiguite de l'operateur, refusant categoriquement toute manipulation manuelle (scp/mot de passe tapes a la main) : "il doit avoir un job qui fait ca ... automatique ... controle tout comme un INTJ qui ne laisse rien passer".

**Cause racine identifiee, pas seulement contournee** : la conception initiale de `DIST_001` (scp authentifie par cle SSH ou mot de passe) exigeait un identifiant partage entre VM1 et VM2, qui ne peut PAS s'auto-generer - quelqu'un doit toujours le deposer manuellement une premiere fois quelque part. Cette meme conception avait deja cause un incident reel le 2026-08-30 (mot de passe root en clair dans `vars.conf`, livre tel quel dans l'archive de deploiement). Deux incidents distincts, meme cause profonde : traiter `factory_ca.crt` comme un secret alors que ce n'en est PAS un - c'est un certificat PUBLIC (seule sa cle privee associee, jamais distribuee, doit rester protegee). Aucune authentification n'est necessaire pour le distribuer, exactement comme le fait toute autorite de certification reelle sur Internet.

**Corrige a la racine, plus aucun identifiant nulle part** :
- **`jobs/PKI_012_SERVE_CA_HTTP.sh`** (nouveau, `ELK_HOST`, `IN_COND=PKI_CRYPTO_ARMED`, `OUT_COND=PKI_CA_HTTP_OK`) : copie `factory_ca.crt` dans un repertoire DEDIE `PKI_PUBLIC_DIR` (jamais `PKI_DIR` en entier, qui contient la cle privee de la CA) - garde-fou reel verifiant qu'aucun autre fichier n'y a jamais ete depose avant de servir quoi que ce soit. Sert ce repertoire via un service systemd permanent (`wef-ca-server.service`, `python3 -m http.server`), port `PKI_CA_HTTP_PORT` (8091, nouvelle variable) ouvert sur la zone `public` (meme constat que `WAZ_006B_FW_DASHAPI` : seule zone reellement liee a l'interface). Verifie en fin de job, par une vraie requete locale comparee au fichier source (`cmp`), que le contenu servi est identique - jamais suppose.
- **`jobs/DIST_001.sh`** (reecrit entierement) : suppression complete de la logique scp/sshpass/FACTORY_SSH_*. Recupere desormais `factory_ca.crt` par `curl` simple, en reessayant reellement jusqu'a 24 fois (2 minutes) si VM1 n'est pas encore joignable - controle explicite de sa disponibilite, jamais un seul essai a froid, repond directement a la demande "controle la disponibilite de la VM". Verifie que le contenu recupere est un vrai certificat X.509 (`openssl x509 -noout`) avant de l'installer - jamais une simple reponse HTTP 200 prise pour argent comptant (meme discipline que la correction PKI_003-009 du 2026-09-09).
- **`vars.conf`** : `FACTORY_SSH_USER`/`FACTORY_SSH_KEY`/`FACTORY_SSH_PASSWORD_FILE` supprimes (plus jamais lus par aucun job) ; nouvelles variables `PKI_PUBLIC_DIR`/`PKI_CA_HTTP_PORT`.
- **`secrets/README_SECRETS.txt`** : entree `factory_ssh_password.txt` retiree (ce fichier n'est plus jamais lu).
- **`jobs_table.csv`** : nouvelle ligne `PKI_012_SERVE_CA_HTTP` entre `PKI_011` et `ES_001`.

**Audit de conformite trouve en meme temps ("reviser tous les jobs")** : `setup/MNT_reinstall.sh` (purge complete pour repartir de zero) ne desinstallait jamais `metricbeat` ni `wazuh-agent` (seulement `filebeat` cote agents) - angle mort jamais remarque faute d'un vrai `AGENT_HOST` deploye avant cette semaine, meme classe d'incident reel que celui documente plus haut pour `ES_021` (residus d'une installation precedente faisant echouer la suivante). Corrige : `metricbeat`/`wazuh-agent` ajoutes aux etapes arret/desactivation/desinstallation/repertoires residuels/depots dnf (`metricbeat.repo`/`filebeat.repo`).

**Verifie** : `bash -n` propre sur les 2 jobs (nouveau + reecrit), `MNT_reinstall.sh` et `vars.conf` ; audit CSV complet (0 doublon `JOB_ID`/`OUT_COND`, tous les `SCRIPT_FILE` existent, seul orphelin `IN_COND` = le gate demo volontaire) ; **simulation de la resolution par vagues rejouee pour les deux roles** apres l'ajout de `PKI_012` : `ELK_HOST` 219/219 en 2 passes, `AGENT_HOST` 53/53 en 3 passes, 0 job bloque des deux cotes (la simulation elle-meme a d'abord donne un faux positif de blocage AGENT_HOST - bug de la simulation, pas du code reel : elle ne gerait pas encore la colonne `COMPONENT` a valeurs multiples separees par `|`, comme `DIST_001,...,FILEBEAT|METRICBEAT,...` - corrigee en relisant `component_enabled()` reel dans `lib/commun.sh` avant de conclure, jamais suppose).

**Limite honnete** : jamais teste en conditions reelles (le service `wef-ca-server`/`python3 -m http.server` n'a jamais tourne sur une vraie VM1 jusqu'ici) - VM1 a deja termine tout son deploiement, `PKI_012_SERVE_CA_HTTP` devra donc y etre force manuellement une fois (`$APP_BIN/order.sh PKI_012_SERVE_CA_HTTP ...`) apres un `git pull`, plutot que rejoue automatiquement par un run complet. A confirmer par le prochain essai reel de `DIST_001` sur VM2.

**Correction du meme jour, apres le premier essai reel** : deux points corriges suite a la sortie reelle de l'operateur.

1. **`order.sh` inutile, corrige de moi-meme** : `PKI_CRYPTO_ARMED` (dependance de `PKI_012`) etait deja rempli depuis le premier deploiement complet de VM1 - un simple `$APP_HOME/orchestrator.sh` suffit a faire jouer automatiquement le seul job restant, sans forcer quoi que ce soit. `order.sh` n'a de sens que pour bypasser une dependance non remplie, ce qui n'etait pas le cas ici.

2. **Echec reel au premier lancement de `PKI_012_SERVE_CA_HTTP` sur VM1** : `wef-ca-server.service` en boucle de redemarrage (`status=2`). Diagnostic demande et obtenu avant toute correction (`python3 --version` -> `3.6.8` ; `python3 -m http.server ... --directory ...` -> `error: unrecognized arguments: --directory`). Cause reelle confirmee : Oracle Linux 8.10 fournit Python 3.6.8 par defaut - l'option `--directory` du module `http.server` n'existe que depuis Python 3.7, jamais verifie avant ce premier essai reel (aucune VM Oracle Linux 8 disponible pour tester `python3 -m http.server` avant aujourd'hui). Corrige sans detection de version : `--directory` retire de `ExecStart` - `WorkingDirectory=` (deja present dans l'unit systemd) place deja le process dans le bon repertoire avant meme l'exec, rendant `--directory` strictement redondant pour ce besoin.

**Verifie** : `bash -n` propre sur `PKI_012_SERVE_CA_HTTP.sh` corrige.

**A faire sur VM1** : `git pull origin main` puis `$APP_HOME/orchestrator.sh` (rejoue uniquement `PKI_012_SERVE_CA_HTTP`, seul job non termine).

**Limite honnete** : toujours pas confirme en reel apres ce correctif - a verifier au prochain relancement.

## 2026-09-13 (suite) - Troisieme incident reel : `PKI_012_SERVE_CA_HTTP` "OK" sur VM1 mais toujours injoignable depuis VM2 - meme piege deja documente dans `LS_008.sh`, pas relu a temps

**Contexte** : le correctif Python 3.6 a bien fonctionne - `PKI_012_SERVE_CA_HTTP -> OK` sur VM1. Mais `DIST_001`, relance sur VM2, echoue quand meme apres 24 essais reels (2 minutes) - `curl` vers `http://192.168.50.128:8091/factory_ca.crt` depuis VM2 echoue.

**Diagnostic mene par etapes reelles, jamais suppose** :
1. Cote VM1 : `ss -tlnp` confirme l'ecoute sur `0.0.0.0:8091` ; `firewall-cmd --zone=public --list-ports` confirme `8091/tcp` present ; `curl` depuis VM1 vers sa propre IP reelle reussit. Tout semblait correct.
2. Cote VM2 : `curl -v` donne "Aucun chemin d'acces pour atteindre l'hote cible" (No route to host) - pas "connexion refusee", donc pas un simple filtrage de port.
3. Meme symptome reproduit sur le port 443 (deja etabli, deja fonctionnel par le passe) depuis VM2 -> ce n'est pas specifique au port 8091, mais un probleme de portee plus large.
4. `ping` VM2->VM1 reussit (0% perte) - donc pas un probleme reseau L2/L3 general.
5. `iptables -S INPUT/OUTPUT` sur VM1 ne montre qu'une politique ACCEPT vide - normal sur Oracle Linux 8, `firewalld` y pilote `nftables`, pas les chaines `iptables` historiques - cette commande ne prouvait donc rien, dans un sens comme dans l'autre.
6. **`firewall-cmd --get-active-zones` sur VM1 revele la cause reelle** : DEUX zones actives - `public` (liee a l'interface `ens160`) ET `CollectZone` (liee non pas a une interface mais a une SOURCE precise, `192.168.50.130/32` = l'IP exacte de VM2). firewalld fait correspondre une zone-source AVANT une zone-interface : tout le trafic venant de VM2 est donc filtre par `CollectZone`, jamais par `public`, quel que soit ce que `public` autorise.

**Cause racine, deja documentee une fois mais pas relue a temps** : `jobs/LS_008.sh` porte, depuis le 2026-08-31, un commentaire qui decrit EXACTEMENT ce meme mecanisme ("SSH refuse alors que le ping passe... firewalld fait correspondre une source AVANT une interface... CollectZone est desormais le proprietaire unique et complet du jeu de ports necessaires a un AGENT_HOST, documente ici pour que ce ne soit jamais suppose implicite"). `PKI_012_SERVE_CA_HTTP.sh` a ete ecrit sans relire ce commentaire - la meme classe d'erreur reapparait faute d'avoir consulte la documentation deja existante avant d'ajouter un nouveau port destine a un AGENT_HOST.

**Corrige (`jobs/PKI_012_SERVE_CA_HTTP.sh`)** : le port est desormais ouvert sur `CollectZone` (essentiel) en plus de `public` (acces direct/local, ne coute rien a garder). **Corrige aussi l'ordre dans `jobs_table.csv`** : `IN_COND` change de `PKI_CRYPTO_ARMED` (bien avant la phase Logstash) a `LS_FW_ARMED` (`OUT_COND` de `LS_009`, une fois `CollectZone` reellement creee ET source-bound par `LS_006`/`LS_008`) - le job tournait auparavant avant meme que la zone cible n'existe.

**Verifie** : `bash -n` propre ; audit CSV complet (0 doublon, tous les `SCRIPT_FILE` existent) ; simulation de resolution par vagues rejouee : `ELK_HOST` 219/219 en 2 passes, `AGENT_HOST` 53/53 en 3 passes, 0 job bloque - `PKI_012` se resout bien a sa nouvelle position, rien d'autre casse.

**A faire sur VM1** : VM1 a deja termine son deploiement avec l'ancien `PKI_012` (a la mauvaise position, `.ok` deja marque) - supprimer son marqueur pour le forcer a rejouer a la bonne place avec le bon correctif :
```bash
git pull origin main
rm -f state/PKI_CA_HTTP_OK.ok
$APP_HOME/orchestrator.sh
```

**Limite honnete** : toujours pas reconfirme en reel apres ce troisieme correctif - a verifier au prochain essai de `DIST_001` sur VM2. Question ouverte, non resolue ici, notee pour une prochaine fois : `CollectZone` n'autorise qu'UNE seule source a la fois (`BEATS_HOST_IP`, remplacee a chaque fois par `LS_008`) - un futur troisieme hote `AGENT_HOST` simultane (VM3) ne serait pas couvert par cette meme regle sans revoir ce mecanisme a source unique.

## 2026-09-13 (suite) - Jalon reel majeur : premier deploiement AGENT_HOST complet, ZERO echec, de bout en bout

**Confirme en reel** : `DIST_001` reussi du premier coup (`CA_DISTRIBUTED_OK`) apres le correctif `CollectZone`/ordre `LS_FW_ARMED` - la chaine entiere `AGENT_HOST` (53 jobs : `DIST_001`, `INFRA_002`, `WAG_001-006`, `FB_001-023`, `MB_001-022`, crash-tests reseau/charge inclus des deux cotes Filebeat/Metricbeat) s'est executee sans un seul echec, jusqu'au tableau de bord final (`bin/summary.sh`, branche `ROLE=AGENT_HOST`) confirmant `filebeat`/`metricbeat`/`wazuh-agent` tous actifs.

**Ferme definitivement toutes les limites honnetes accumulees depuis la creation de ce role** : `INFRA_006_AGENT_RESOURCE_CHECK` ("jamais teste en conditions reelles", depuis le 2026-08-31), `WAG_005` (corrige par anticipation le 2026-09-13, jamais encore observe en situation reelle), `DIST_001`/`PKI_012_SERVE_CA_HTTP` (les 3 incidents reels du jour, tous corriges et maintenant confirmes). Premiere preuve complete, de bout en bout, que le role `AGENT_HOST` de cette usine fonctionne reellement - pas seulement en audit statique.

**Note mineure, sans consequence fonctionnelle** : le tableau de bord affiche `AGENT_NAME=mon-agent-01` - la valeur du modele `vars.local.conf.example`, jamais personnalisee sur cette VM avant ce lancement. L'enregistrement Wazuh a reussi normalement malgre ce nom generique ; a renommer avant un futur second `AGENT_HOST` simultane pour eviter toute ambiguite dans la liste des agents.

**Rien a corriger** - entree de confirmation.

## 2026-09-13 (suite) - Scenario metier BEAC (LCB-FT + CyrielleMoney) - developpe sur la branche demo-donnees-realistes

**Demande explicite** : "l'etudiante fait le stage a la BEAC... simuler les collectes... donnees LCB-FT... des index dans Kibana propres a ca... je voudrais donner la racine des index dans vars.conf comme par exemple ambargo ou mission... le format que vous avez l'habitude de creer... latence d'1s et parfois meme 5 enregistrements d'un coup... des transferts d'argent national et a l'international, application CyrielleMoney, journaux comme s'ils provenaient de Glassfish... tout ca doit etre des jobs."

**Difference architecturale assumee avec AnkrrWEF (entree precedente)** : l'utilisateur decrit explicitement des enregistrements "s'ecrivant dans le fichier" et qui doivent "apparaitre dans leur index Kibana" une fois ecrits - pas un appel direct a l'API Elasticsearch. Choix : un job ECRIT dans un fichier (comme une vraie application qui journalise), et c'est LOGSTASH (deja en place, LS_020/LS_024) qui le lit en direct et l'indexe - reutilise l'infrastructure existante plutot que d'ajouter un mecanisme parallele, et se rapproche davantage d'une vraie chaine de collecte que le mecanisme direct-API d'AnkrrWEF.

**Recherche prealable, jamais devinee** : lecture de `LS_020.sh` (entrees) et `LS_024.sh` (sorties) avant de toucher quoi que ce soit - revele que TOUT le pipeline actuel route vers UN SEUL index generique (`${ES_INDEX_NAME_PREFIX}-*`), sans distinction par source. Un routage par type devait donc etre ajoute, pas suppose deja possible.

**Construit** :
- `vars.conf` : `LCBFT_INDEX_PREFIX` (defaut `"ambargo"`, choix arbitraire entre les 2 propositions de l'utilisateur - facilement renommable), `LCBFT_LOG_FILE`, `LCBFT_SEED_MIN_COUNT`/`MAX_COUNT` (1/5 - tirage aleatoire a chaque declenchement, demande explicite pour refleter "parfois 1, parfois 5 d'un coup"), `CYRIELLEMONEY_INDEX_PREFIX` (defaut `"cyriellemoney"`), `CYRIELLEMONEY_LOG_FILE`.
- `jobs/lib/beac_scenario_tools.sh` (nouveau) : `seed_lcbft_detections_file()` (ecrit N detections, N tire aleatoirement entre les bornes vars.conf, 10 natures variees - seuils especes, structuration, zone a risque, PPE, virements rapides, faux documents, multiplication de beneficiaires, retrait atypique, liste de surveillance interne) et `seed_cyriellemoney_transfers_file()` (transferts national/international, `app_server` Glassfish explicite, statuts ponderes realiste).
- **CHOIX ASSUME, documente dans le code** : les "zones a risque" des detections LCB-FT utilisent des codes FICTIFS (`ZONE-RISQUE-A/B/C`), jamais un vrai nom de pays - une donnee de demo ne doit jamais laisser croire a une affirmation reelle sur le statut d'embargo d'un pays reel. Les pays CEMAC cites pour les transferts normaux (CyrielleMoney, LCB-FT hors risque) restent de la geographie neutre.
- `jobs/LS_020.sh` : 2 entrees `file` ajoutees (lecture en direct façon "tail -f", `sincedb_path` dedie par fichier - jamais `/dev/null`, pour ne jamais reindexer tout l'historique a chaque redemarrage Logstash), taguees `type => "lcbft_detection"` / `type => "cyriellemoney_transfer"`.
- `jobs/LS_024.sh` : sortie restructuree en `if/else if/else` pour un routage MUTUELLEMENT EXCLUSIF par type - LCB-FT et CyrielleMoney vont UNIQUEMENT vers leur propre index, jamais aussi vers `log-*`/fichier/S3 generiques. Lignes d'authentification ES (token/mot de passe) extraites en variable partagee, reutilisees dans les 3 branches sans divergence possible.
- 4 nouveaux jobs manuels (meme famille `WAZ_PURGE_MANUAL_GATE` que `WAZ_045-049C`, jamais dans la chaine automatique) : `WAZ_049D_SEED_LCBFT_LIVE`, `WAZ_049E_PURGE_LCBFT`, `WAZ_049F_SEED_CYRIELLEMONEY_LIVE`, `WAZ_049G_PURGE_CYRIELLEMONEY` (purge = index Elasticsearch + vidage du fichier de log).
- `docs/GUIDE_EXPLOITATION.md` : nouvelle section 6 dediee, avec les commandes de prealable (rejouer `LS_020`/`LS_024`/`LS_026_FINAL` pour appliquer la nouvelle config Logstash) et d'usage.

**Verifie** : `bash -n` propre sur les 4 nouveaux jobs + `LS_020.sh`/`LS_024.sh`/`beac_scenario_tools.sh`/`vars.conf` ; les 2 blocs Python embarques compilent (`compile()`) ; bit executable Git corrige ; audit CSV complet (281 lignes, 0 doublon `JOB_ID`/`OUT_COND`, tous les `SCRIPT_FILE` existent, 12 jobs derriere le gate manuel, toujours inatteignable automatiquement) ; simulation de resolution par vagues rejouee : `ELK_HOST` 219/219, `AGENT_HOST` 53/53, 0 bloque ; **texte Logstash genere reellement rendu et relu a la main** (extraction de la logique de construction de chaine dans un script de test isole, sans toucher au systeme) pour verifier l'equilibre des accolades et la structure `if/else if/else` du nouveau routage - correct des 2 cotes (entrees et sorties).

**Limite honnete** : jamais teste contre un vrai Logstash/Elasticsearch - la logique de generation de config a ete verifiee TEXTUELLEMENT (rendu manuel), mais jamais chargee par un vrai processus Logstash pour confirmer qu'elle demarre sans erreur de parsing. Reste sur la branche `demo-donnees-realistes`, jamais fusionne sur `main` sans validation explicite ET test reel prealable - ce scenario touche `LS_020`/`LS_024`, deux fichiers deja verrouilles en immuable (`LS_036_FINAL`) sur toute VM1 deja deployee : leur application reelle necessitera de rejouer ces jobs (dont le code gere deja le deverrouillage temporaire, `chattr -i`) puis de redemarrer Logstash (`LS_026_FINAL`).

## 2026-09-13 (suite) - Correction architecturale majeure du scenario BEAC : les donnees doivent naitre sur AGENT_HOST et remonter, pas etre ecrites sur ELK_HOST

**Remarque explicite et juste de l'operateur, immediatement apres l'entree precedente** : "ce fichier doit etre sur la VM ou sont les agents, donc il doit avoir une remontee d'informations... je vous ai dit que les donnees doivent quitter des VM clientes ou sont installes les agents pour remonter vers les serveurs (logstash, kibana, elasticsearch)." Erreur de conception reelle et reconnue : la version precedente faisait ecrire les 2 fichiers de log directement sur `ELK_HOST`, avec des entrees `file{}` Logstash LOCALES pour les relire sur place - au mepris du principe fondateur de toute cette usine (les donnees naissent sur une machine cliente et REMONTENT via Filebeat, jamais l'inverse), principe pourtant deja demontre exhaustivement par FB_012/LS_020 (bloc `beats`) pour tout le reste du projet.

**Corrige de fond en comble, jamais un simple correctif de surface** :
1. **`jobs/LS_020.sh` revert INTEGRAL** (`diff` confirme identique a `main`) - les 2 entrees `file{}` ajoutees par erreur sont retirees. Logstash n'a besoin d'AUCUNE nouvelle entree : le canal `beats{}` deja existant (port `LS_BEATS_PORT`, deja utilise par Filebeat/Metricbeat) suffit.
2. **`vars.conf`** : `LCBFT_LOG_FILE`/`CYRIELLEMONEY_LOG_FILE` deplaces de `/var/log/beac/*.log` (sous-repertoire invente) a `/var/log/*.log` directement - DELIBEREMENT choisi pour tomber dans le prospecteur Filebeat GENERIQUE deja existant (`FB_007.sh`, `paths: - /var/log/*.log`) : aucune configuration Filebeat dediee necessaire, ces 2 fichiers sont traites exactement comme n'importe quel autre log de l'hote.
3. **`jobs/BEAC_001_SEED_LCBFT_LIVE.sh`/`BEAC_002_SEED_CYRIELLEMONEY_LIVE.sh`** (renommes depuis `WAZ_049D`/`WAZ_049F` - `git mv`, historique préservé) : `JOB_ROLE` passe de `ELK_HOST` a `AGENT_HOST`, `COMPONENT=FILEBEAT` (le scenario exige que Filebeat tourne sur cette machine pour expedier le fichier). Renommage motive aussi par la clarte : un prefixe `WAZ_` sur un job `AGENT_HOST` aurait ete trompeur (toute la famille `WAZ_*` est jusqu'ici strictement `ELK_HOST`) - nouveau prefixe `BEAC_`, jamais utilise ailleurs, sans ambiguite de role.
4. **`jobs/LS_023B_BEAC_FILTER.sh`** (nouveau, remplace le raisonnement "type pose par l'entree file" devenu obsolete) : puisque les evenements arrivent desormais par le canal `beats{}` generique (aucun moyen d'y poser un `type` distinct a l'entree comme le faisait l'ancienne entree `file{}` dediee), la reconnaissance se fait par le champ ECS `[log][file][path]` que Filebeat ajoute LUI-MEME a chaque evenement (jamais invente ici) - `filter { if [log][file][path] =~ "...\.log$" { json { source => "message" } } }`, pour parser le contenu JSON (Filebeat livre chaque ligne brute non parsee dans `message`). Inseree dans la chaine de filtres existante (`LS_021`->`LS_022`->`LS_023`->**`LS_023B_BEAC_FILTER`**->`LS_024`), meme convention de fichier numerote (`12-beac-filter.conf`) que `10-privacy-filter.conf`/`11-enrichment.conf` deja en place.
5. **`jobs/LS_024.sh`** : routage de sortie corrige pour tester `[log][file][path]` (meme champ que le filtre ci-dessus, une seule source de verite) au lieu de l'ancien `[type]` qui n'existait plus.
6. **`jobs/WAZ_049E_PURGE_LCBFT.sh`/`WAZ_049G_PURGE_CYRIELLEMONEY.sh`** : restent `ELK_HOST` (la purge d'index Elasticsearch reste locale a cette machine) mais la logique de troncature du fichier de log est RETIREE (code mort - ce fichier ne vit plus jamais sur `ELK_HOST`) ; commentaire ajoute pointant vers la commande manuelle equivalente a executer sur `AGENT_HOST` si besoin.

**Bug reel trouve en auditant apres coup, jamais suppose correct** : les nouvelles descriptions `jobs_table.csv` contenaient chacune une VRAIE virgule non echappee dans un champ non protege ("bin/order.sh, sur AGENT_HOST") - un decalage de colonnes silencieux (IN_COND/OUT_COND corrompus pour ces 4 lignes), detecte uniquement parce que l'audit CSV habituel a ete rejoue et a signale 3 doublons `OUT_COND` inattendus plutot que d'etre suppose bon apres une simple relecture visuelle. Corrige (virgule retiree du texte).

**Verifie** : `bash -n` propre sur tous les fichiers touches ; audit CSV complet REJOUE APRES le bug ci-dessus et sa correction (282 lignes, 0 doublon `JOB_ID`/`OUT_COND`, 0 ligne a nombre de colonnes incorrect, tous les `SCRIPT_FILE` existent) ; simulation de resolution par vagues : `ELK_HOST` 220/220, `AGENT_HOST` 53/53, 0 bloque ; `diff` confirmant `LS_020.sh` strictement identique a `main` apres le revert ; texte Logstash re-rendu a la main pour le nouveau filtre et le nouveau routage par chemin.

**Limite honnete, inchangee** : toujours jamais teste contre un vrai Logstash/Elasticsearch/Filebeat - en particulier, la capacite reelle du champ `[log][file][path]` a arriver dans cette forme exacte via le canal `beats{}` (dependant de la version de Filebeat/du codec ECS reellement utilise) n'a jamais ete verifiee en conditions reelles. Reste sur la branche `demo-donnees-realistes`.

## 2026-09-13 (suite) - Cause reelle trouvee : `action.auto_create_index` bloquait silencieusement `ambargo-*`/`cyriellemoney-*`

**Contexte** : premier essai reel du scenario BEAC de bout en bout (fichier ecrit sur AGENT_HOST, Filebeat, Logstash) - `ambargo-*` reste a 0 document malgre plusieurs tentatives, harvester Filebeat confirme actif, aucune erreur dans les journaux Filebeat NI Logstash. Diagnostic mene entierement en direct avec l'operateur, par elimination systematique - chaque hypothese testee avec une preuve reelle avant d'etre abandonnee :
1. Config Logstash mal generee ? Non - `cat` confirme le contenu exact attendu des deux cotes (filtre + sortie).
2. Mauvais nom de champ (`[log][file][path]`) ? Non - confirme correct par un vrai document indexe (`/var/log/messages`).
3. Filebeat n'a pas remarque le fichier ? Non - harvester demarre confirme dans `journalctl -u filebeat`, exactement au moment de l'ecriture.
4. Connexion Filebeat->Logstash coupee (redemarrage Logstash en cours) ? Vrai UNE FOIS (incident reel distinct, deja documente), mais pas la cause du blocage persistant apres stabilisation.
5. Condition de routage jamais vraie ? Non - **statistiques internes du plugin de sortie Logstash** (`_node/stats/pipelines/main`, plugin par plugin) montrent EXACTEMENT le bon nombre d'evenements ("in"=5, "out"=5, correspondant pile a un lot de 5 detections) sur le plugin Elasticsearch dedie - la condition matche bel et bien, et Logstash considere l'envoi reussi.
6. Erreur silencieuse cote Elasticsearch, jamais loggee avec les mots-cles deja essayes ? **Confirme** : `GET _cluster/settings?include_defaults=true` revele `action.auto_create_index: "log-*,wazuh-*,-*"` - un disjoncteur de securite DEJA EN PLACE (`ES_041.sh`, pose deliberement il y a longtemps, meme classe d'incident deja rencontree une fois avec `ES_046`/"factory-stresstest", voir plus haut dans ce journal) qui refuse la creation de tout index hors de cette liste blanche explicite - "ambargo-*"/"cyriellemoney-*" n'y figuraient pas. Logstash envoie sa requete groupee (d'ou "out"=5, un succes de transport HTTP), mais Elasticsearch refuse de creer l'index lui-meme - un rejet qui ne remonte pas forcement comme une "exception" bruyante cote Logstash pour ce type d'erreur precis.

**Corrige (`jobs/ES_041.sh`)** : la liste blanche est ETENDUE (jamais desactivee - le principe de durcissement reste intact) pour inclure `${LCBFT_INDEX_PREFIX}-*`/`${CYRIELLEMONEY_INDEX_PREFIX}-*` en plus de `log-*`/`wazuh-*`, lues depuis `vars.conf` (jamais codees en dur - si l'operateur renomme un jour ces prefixes, la liste blanche suit automatiquement). Retro-compatible : sur une VM `main` (sans ces 2 variables), le comportement reste identique bit pour bit a avant (verifie par simulation bash des deux cas, avec et sans les variables).

**Verifie** : `bash -n` propre ; rendu du JSON genere verifie a la main dans les deux cas (avec/sans variables BEAC) - `log-*,wazuh-*,ambargo-*,cyriellemoney-*,-*` et `log-*,wazuh-*,-*` respectivement, tous deux corrects.

**A faire pour appliquer sur VM1** : `ES_041` a deja tourne une fois avec l'ancienne liste (`.ok` deja marque) - le rejouer pour appliquer la nouvelle liste blanche :
```bash
git pull origin demo-donnees-realistes
rm -f state/ES_AUTO_BLOCK_OK.ok
$APP_BIN/order.sh ES_041 "extension liste blanche pour le scenario BEAC"
```
Puis rejouer le seed LCB-FT sur VM2 - aucun redemarrage de Logstash necessaire cette fois (le reglage `auto_create_index` est un parametre de CLUSTER Elasticsearch, pas une config Logstash - s'applique immediatement, sans redemarrage d'aucun service).

**Limite honnete** : toujours pas confirme par un document reellement visible dans `ambargo-*` au moment de cette entree - la cause est identifiee avec un tres haut degre de confiance (preuve directe du reglage cluster bloquant), mais la confirmation finale (compter a nouveau apres ce correctif) reste a faire.

## 2026-09-13 (suite) - Confirme en reel : la chaine complete fonctionne, `ambargo-*` recoit ses premiers documents

**Confirme** : apres application reelle du correctif `ES_041` sur VM1 (`Motifs autorises : log-*,wazuh-*,ambargo-*,cyriellemoney-*,-*`) et ecriture d'un nouveau lot de detections sur VM2 (celles ecrites AVANT le correctif etaient deja perdues, rejetees et abandonnees par Logstash au moment de l'echec - jamais recuperables retroactivement, un nouveau lot etait necessaire), `curl .../ambargo-*/_count` renvoie enfin `{"count":3}`.

**Chaine bout en bout validee pour la premiere fois** : fichier ecrit sur `AGENT_HOST` (`BEAC_001_SEED_LCBFT_LIVE`) -> Filebeat (prospecteur generique `FB_007`, aucune config dediee) -> Logstash sur `ELK_HOST` (`beats{}` -> `12-beac-filter.conf` -> `30-outputs.conf`, reconnaissance et routage par `[log][file][path]`) -> Elasticsearch (`ambargo-*`, desormais autorise par `ES_041`) -> visible dans Kibana (Data View a creer manuellement au premier essai, meme regle que `AnkrrWEF`).

**Retrospective honnete sur la duree de ce diagnostic** : gagne uniquement par elimination methodique de CHAQUE etape reelle du pipeline (config Logstash, nom de champ, harvester Filebeat, connexion reseau, condition de routage via les statistiques internes du plugin, puis enfin le reglage cluster) - jamais par une supposition non verifiee acceptee comme suffisante. La cause finale (`action.auto_create_index`) etait un reglage de securite deja en place depuis longtemps dans ce meme projet, jamais reconsidere avant parce que sa seule autre collision connue (`ES_046`/incident 10) avait ete resolue autrement (renommage d'index) sans jamais toucher a ce reglage - premiere fois qu'un NOUVEAU prefixe d'index legitime devait y etre ajoute explicitement.

**Reste a faire, non urgent** : confirmer `CyrielleMoney` (`BEAC_002_SEED_CYRIELLEMONEY_LIVE`) de la meme facon - meme mecanisme, meme correctif deja en place (`cyriellemoney-*` deja dans la liste blanche `ES_041`), tres probablement deja fonctionnel mais jamais teste en reel a ce jour. Fusion sur `main` toujours en attente de validation explicite de l'utilisateur.

## 2026-09-13 (suite) - `ES_041` simplifie : liste blanche generique dans vars.conf, plus jamais besoin de modifier ce fichier

**Demande explicite** : "meme ca (ambargo-*) un job doit s'en occuper... il doit avoir une ligne dans vars.conf un peu comme un allow[aut]ho[r]iz[e]d[connect]ssh ou l'on peut lister les noms des comptes autorises a se connecter par ssh mais ici c'est les racines des noms d'index... tout ce qu'il y aura a cette ligne leur index doit etre cree."

**Corrige (`jobs/ES_041.sh`)** : au lieu de verifier individuellement `LCBFT_INDEX_PREFIX`/`CYRIELLEMONEY_INDEX_PREFIX` (ce qui obligeait a modifier ce fichier a chaque nouveau scenario), lit desormais une seule liste generique **`ES_DEMO_INDEX_PREFIXES`** (nouvelle variable `vars.conf`, separee par des virgules, tolerante aux espaces) - exactement le modele "liste blanche" demande, calque sur l'exemple SSH donne par l'operateur. Ajouter un futur scenario de demo (un 3e, un 4e...) ne touchera plus jamais `ES_041.sh` : juste ajouter son prefixe a cette ligne.

**Verifie** : `bash -n` propre ; rendu du motif final verifie a la main dans 3 cas (liste normale, liste absente/vide - comportement `main` inchange, liste avec espaces superflus) - les 3 corrects.

**A appliquer sur VM1 (si deja deployee avec l'ancien `ES_041.sh`)** :
```bash
git pull origin demo-donnees-realistes  # ou "git merge origin/demo-donnees-realistes" si branches divergentes
rm -f state/ES_AUTO_BLOCK_OK.ok
$APP_BIN/order.sh ES_041 "passage a la liste blanche generique ES_DEMO_INDEX_PREFIXES"
```

## 2026-09-13 (suite) - Nouveau job dedie pour une demo "presentation live" (jamais un vars.conf a retoucher a la main)

**Demande explicite, avec critique justifiee** : pour la premiere demo de l'etudiante, l'operateur voulait 50 detections LCB-FT a 2s d'intervalle (au lieu du defaut 1-5 aleatoire/1s) - la reponse initialement proposee (`sed` sur `vars.conf` avant de lancer) a ete refusee a raison : "l'INTJ dans tout ce bidouillement de ce soir aurait pratique quoi ?".

**Corrige en appliquant un principe deja etabli ailleurs dans ce meme projet, jamais reapplique ici par oubli** : `WAZ_045A_SEED_INDEXER_DATA` (bulk/test de charge) et `WAZ_048_SEED_INDEXER_LIVE` (remplissage visible normal) sont deja 2 jobs DISTINCTS avec leurs propres reglages, jamais un seul job reconfigure a la main selon l'usage. Meme logique appliquee ici :
- **`jobs/BEAC_003_SEED_LCBFT_BULK_LIVE.sh`** (nouveau) : nombre FIXE (jamais aleatoire, contrairement a `BEAC_001`) de detections, a un rythme dedie - reutilise `seed_lcbft_detections_file()` deja existante (meme min/max = nombre fixe, aucun changement de bibliotheque necessaire).
- **`vars.conf`** : `LCBFT_DEMO_BULK_COUNT` (defaut 50), `LCBFT_DEMO_BULK_INTERVAL_SEC` (defaut 2) - reglages PERMANENTS et dedies, jamais a modifier pour lancer une demo, contrairement au `sed` initialement propose.
- `jobs_table.csv` : nouvelle ligne, meme famille (`WAZ_PURGE_MANUAL_GATE`, `AGENT_HOST`/`FILEBEAT`) - description ecrite SANS virgule non protegee cette fois (lecon du bug de decalage de colonnes trouve plus tot dans la soiree, verifiee explicitement par l'audit CSV rejoue).

**Verifie** : `bash -n` propre ; bit executable corrige ; audit CSV complet (283 lignes, 0 doublon, 0 ligne a colonnes incorrectes) ; simulation de resolution par vagues : `ELK_HOST` 220/220, `AGENT_HOST` 53/53, 0 bloque.

**Limite honnete** : jamais teste en conditions reelles (nouveau job, meme mecanisme deja confirme fonctionnel pour `BEAC_001` - risque residuel tres faible, mais pas encore une preuve directe pour celui-ci precisement).

## 2026-09-13 (suite) - Nouveau job pour rendre les Data Views Kibana automatiques (capture d'ecran reelle : `ambargo-*` absent du selecteur)

**Constat reel, capture d'ecran a l'appui** : dans Kibana Discover, le selecteur "Data view" ne proposait que "All logs" et "Wazuh Alerts", malgre des documents deja presents dans `ambargo-*` (confirme plus tot par `_count`). Cause connue et deja documentee ailleurs dans ce projet pour `AnkrrWEF` : ecrire des documents dans un index ne cree jamais automatiquement l'objet Kibana "Data View" necessaire pour le voir dans Discover - jusqu'ici traite comme une etape manuelle ("Creez le Data View... au premier essai"), jamais automatisee.

**Corrige** : nouveau job **`jobs/BEAC_004_CREATE_KIBANA_DATAVIEWS.sh`**, `ELK_HOST`/`ALWAYS`, `IN_COND=KB_NOMINAL_OK|ES_AUTO_BLOCK_OK`, `OUT_COND=BEAC_KIBANA_DATAVIEWS_OK`. Generique par construction (jamais "ambargo"/"cyriellemoney" codes en dur) : lit **`ES_DEMO_INDEX_PREFIXES`** (la meme liste blanche que `ES_041`) et cree, via l'API Kibana `POST /api/data_views/data_view` (meme authentification `elastic`/mot de passe bootstrap et header `kbn-xsrf` que `jobs/KB_025.sh`/`jobs/WAZ_036_KIBANA_INDEX.sh`), un Data View par prefixe - `id` deterministe (`<prefixe>-dataview`) + `override:true` pour rester idempotent si le job est rejoue (ex: apres l'ajout d'un nouveau prefixe). Contrairement a `WAZ_036_KIBANA_INDEX.sh` (pas de verification d'erreur), reprend ici la discipline etablie par l'audit `KB_025` : code HTTP verifie explicitement, corps de reponse affiche en cas d'echec.

**Design deliberement non manuel** : contrairement a `BEAC_001`/`002`/`003` (donnees de demo, doivent rester un acte volontaire), rendre un index VISIBLE dans Kibana est une etape d'infrastructure, pas une donnee metier simulee - ce job depend de conditions reelles deja satisfaites (`KB_NOMINAL_OK`, `ES_AUTO_BLOCK_OK`), jamais du gate manuel `WAZ_PURGE_MANUAL_GATE`. Verifie par simulation : `BEAC_KIBANA_DATAVIEWS_OK` se resout automatiquement des le premier passage, `./orchestrator.sh` seul suffit sur une installation lancee a partir de zero - aucun forcage necessaire dans ce cas, contrairement aux 4 jobs BEAC precedents qui avaient du etre forces un par un sur une VM deja entierement deployee avant leur creation.

**Verifie** : `bash -n` propre ; bit executable corrige ; audit CSV complet (285 lignes, 0 doublon d'ID, 0 doublon d'OUT_COND, 0 ligne a colonnes incorrectes) ; simulation de resolution par vagues : `ELK_HOST` 218/228 auto-resolus (10 bloques = exactement les jobs de demo/purge manuels deja connus, aucun nouveau blocage), `AGENT_HOST` 50/53 (3 bloques = `BEAC_001`/`002`/`003`, attendu).

**A appliquer sur une VM1 deja deployee avant ce job** (comme les 4 precedents, puisque `.ok` n'existe pas encore mais que la VM ne relancera pas `./orchestrator.sh` en entier d'elle-meme) :
```bash
git pull origin demo-donnees-realistes  # ou ./bin/sync_branch.sh demo-donnees-realistes si divergence
echo "BEAC_004_CREATE_KIBANA_DATAVIEWS" | $APP_BIN/order.sh BEAC_004_CREATE_KIBANA_DATAVIEWS "creation data views BEAC"
```

**Limite honnete** : jamais confirme en conditions reelles a l'instant de cette entree (nouveau job, mecanisme identique et deja confirme fonctionnel pour `WAZ_036_KIBANA_INDEX.sh`/Wazuh - risque residuel faible mais pas encore une preuve directe pour celui-ci). A confirmer : relancer la commande ci-dessus puis rafraichir le selecteur "Data view" dans Kibana.

## 2026-09-14 - Cause reelle du "rien ne s'affiche" malgre des documents confirmes : ecart d'horloge VM1/VM2

**Constat reel** : `ambargo-*`/`cyriellemoney-*` confirmes non vides par `_count` (53 puis 100 documents), Data Views crees (`BEAC_004`), et pourtant toujours rien dans Discover meme avec le bon data view selectionne. Diagnostic demande explicitement (`date -u` sur les 2 VMs + `_search` trie par `@timestamp` sur le document le plus recent) plutot que de faire retester des boutons un par un :
- VM1 (`wef-elk-core`) : `date -u` -> `22:59:37 UTC`.
- VM2 (`wef-beats-sensor`) : `date -u` -> `23:59:56 UTC`.
- Document `ambargo-*` le plus recent : `"@timestamp":"2026-09-13T23:37:06.861Z"`.

**Cause reelle, jamais suspectee avant d'avoir la preuve** : le champ `@timestamp` d'un evenement Filebeat est fixe par **l'horloge de la machine qui LIT le fichier source** (VM2, au moment du harvest), jamais par Logstash sur VM1 au moment du traitement - confirme par le fait que le document le plus recent porte une heure proche de celle de VM2 (23:37), pas de VM1 (22:59, donc ANTERIEURE au moment ou Logstash a reellement traite l'evenement - un `@timestamp` "dans le futur" du point de vue de VM1). Environ 1h d'ecart entre les 2 VMs (jamais synchronisees par NTP jusqu'ici, chacune derivant independamment) suffit a placer silencieusement les evenements hors de la fenetre de temps par defaut de Kibana Discover, sans aucune erreur, aucun log, rien a voir avec le pipeline Filebeat/Logstash/Elasticsearch lui-meme (deja valide fonctionnel plus tot dans la soiree).

**Corrige - 2 nouveaux jobs, jamais un script a lancer a la main** (demande explicite : adapter un script chrony reel d'une mission precedente de l'operateur, "un INTJ dirait quoi ?") :
- **`jobs/INFRA_007_NTP_SERVER.sh`** (`ELK_HOST`, `IN_COND=LS_FW_5044_OK`, `OUT_COND=NTP_SERVER_OK`) : installe chrony, VM1 devient la source de temps de reference pour VM2 (`allow ${BEATS_HOST_IP}/32`, port 123/udp ouvert sur `CollectZone` - deja source-restreinte a `BEATS_HOST_IP` par `LS_008`, donc rien de plus a securiser ici), avec repli `local stratum 10` pour continuer a servir une heure coherente meme sans acces internet. Tente en plus une synchronisation reelle via `NTP_UPSTREAM_POOL` (nouvelle variable `vars.conf`, defaut `pool.ntp.org`, vide si lab isole).
- **`jobs/INFRA_008_NTP_CLIENT.sh`** (`AGENT_HOST`, `IN_COND=AGENT_RESOURCES_OK`, `OUT_COND=NTP_CLIENT_OK`) : installe chrony, VM2 se synchronise UNIQUEMENT sur VM1 (`FACTORY_HOST_IP`) - jamais sur un pool externe directement, meme principe de source unique de verite que le reste de cette usine (PKI, Logstash...). Force une correction IMMEDIATE (`chronyc makestep`) plutot que de laisser chronyd corriger un ecart d'1h progressivement (bien trop lent avant une demo).

**Adaptation du script original, jamais une copie telle quelle** : le script fourni (mission precedente de l'operateur) ciblait des serveurs NTP internes d'entreprise (IPs privees) et un sed avec des motifs `centos.pool.ntp.org` deja inadaptes a Oracle Linux (bloc vendor different, le sed original n'aurait rien commente du tout sur cette VM - bug latent jamais declenche car jamais teste sur cet OS). Remplace par : (1) le modele deja etabli dans cette usine (VM1 source unique de verite, jamais l'inverse), (2) une commande `sed` generique qui commente TOUTE ligne `server `/`pool ` existante quelle que soit sa formulation, jamais une liste de motifs figee a un OS precis, (3) un marqueur de bloc (`WEF_NTP_SERVER_CONFIG`/`WEF_NTP_CLIENT_CONFIG`) pour rester idempotent a chaque rejeu (meme discipline que la lecon `LS_008`/"residu jamais nettoye").

**Verifie** : `bash -n` propre sur les 2 jobs ; bits executables corriges ; audit CSV complet (286 lignes, 0 doublon d'ID, 0 doublon d'OUT_COND, 0 dependance introuvable) ; simulation de resolution par vagues : `ELK_HOST` 219/229 (10 bloques = les memes jobs de demo/purge manuels deja connus, aucun nouveau blocage), `AGENT_HOST` 51/54 (3 bloques = `BEAC_001`/`002`/`003`, attendu) ; `NTP_SERVER_OK` et `NTP_CLIENT_OK` se resolvent tous les deux automatiquement des le premier passage.

**Limite honnete** : jamais confirme en conditions reelles a l'instant de cette entree (nouveau job, jamais teste sur les VMs reelles) - a appliquer sur VM1 puis VM2, puis reverifier `date -u` sur les 2 machines pour confirmer la convergence, avant de retenter l'affichage dans Kibana Discover.

## 2026-09-14 (suite) - Confirme en reel : NTP corrige, plus une seconde cause distincte trouvee (cache de champs Kibana)

**Confirme en reel** : `INFRA_007_NTP_SERVER` puis `INFRA_008_NTP_CLIENT` appliques sur VM1/VM2 - `chronyc makestep` a corrige immediatement l'ecart (`+3599.7s`, quasi exactement l'heure diagnostiquee), les 2 VMs convergent (`chronyc tracking` : `System time : 0.000000000 seconds fast of NTP time` sur VM2 juste apres correction). `ambargo` s'affiche alors immediatement dans Discover (50 documents, timestamps corrects).

**Mais `cyriellemoney` restait vide meme apres ce correctif** - "Search entire time range" sans effet, alors que `_count` (100), `_mapping/field/@timestamp` (`type: date`, correct) et `_cat/indices` (un seul index reel, `cyriellemoney-2026.09.13`) confirmaient cote Elasticsearch que tout etait parfaitement en ordre. Cause reelle, distincte de l'ecart d'horloge : **le Data View Kibana `cyriellemoney` avait ete cree par `BEAC_004` a un moment ou l'index n'existait pas encore** (aucun document, `BEAC_002` n'avait pas encore tourne a ce moment-la) - contrairement a `ambargo`, qui avait deja 3 documents de test au moment ou `BEAC_004` a tourne. Kibana a fige une liste de champs vide pour `cyriellemoney`, jamais rafraichie toute seule ensuite meme apres l'arrivee des 100 documents.

**Corrige (manuellement, pas un bug de code)** : Stack Management -> Data Views -> `cyriellemoney` -> rafraichissement de la liste des champs -> Save. Confirme en reel : les 100 documents apparaissent immediatement apres, sans meme avoir besoin d'elargir la fenetre de temps.

**Lecon pour un futur scenario** : creer un Data View Kibana (`BEAC_004` ou equivalent) AVANT qu'un premier document existe dans l'index cible produit un cache de champs vide et durable - preferer lancer `BEAC_004` (ou le rejouer, `override:true` deja en place) APRES qu'au moins un document reel existe, ou prevoir un rafraichissement manuel une fois pour un scenario tout neuf. Non corrige dans le code a ce jour (pas demande) - documente ici pour que ce ne soit plus jamais une surprise.

## 2026-09-14 (suite) - Nouveau job de nettoyage global : purge tous les index Elasticsearch sauf la famille Wazuh

**Demande explicite** : "je veux un job qui nettoie les index sur elasticsearch sauf les alert wazuh ... pas un index qui nettoie juste un index j'ai dit tout sauf les alertes wazuh parce que reellement les alertes wazuh appartiennent a la famille de wazuh donc ils sont juste en location chez elasticsearch."

**Corrige (`jobs/ES_064_PURGE_ALL_EXCEPT_WAZUH.sh`, `ELK_HOST`, `IN_COND=WAZ_PURGE_MANUAL_GATE`, `OUT_COND=ES_PURGE_ALL_EXCEPT_WAZUH_OK`)** : contrairement aux purges existantes (`WAZ_046/047/049E/049G`, chacune un pattern d'index fige en dur), celui-ci **decouvre dynamiquement** la liste reelle des index presents (`_cat/indices?h=index`) au moment de l'execution et exclut uniquement ce qui commence par `wazuh-` (interprete au sens large - toute la famille : `wazuh-alerts-4.x-*` confirme deja utilise par `WAZ_047`, plus `wazuh-monitoring-*`/`wazuh-statistics-*` si presents un jour cote Elasticsearch en mode convergent - jamais seulement `wazuh-alerts-*` au sens strict, principe de precaution sur une operation irreversible). Un futur scenario metier ou un futur index de test tombe donc automatiquement dans son perimetre, sans jamais modifier ce script.

**Securites reprises du reste du projet, aucune reinventee** : `IN_COND=WAZ_PURGE_MANUAL_GATE` (jamais satisfaite ailleurs, donc jamais automatique) ; reutilise `purge_index_pattern()` deja existant (`jobs/lib/test_data_tools.sh`, deja utilise par 4 autres jobs) - "purge" signifie ici VIDER le contenu (`_delete_by_query`), jamais supprimer la structure/le mapping de l'index, coherent avec le reste du projet ; les index caches/systeme (`.kibana*`, `.security*`, prefixes par un point) sont deja exclus nativement par `_cat/indices` sans `expand_wildcards=all` - aucun risque de casser Kibana lui-meme, jamais eu besoin de les exclure explicitement.

**Verifie** : `bash -n` propre ; bit executable corrige ; audit CSV complet (287 lignes, 0 doublon d'ID, 0 doublon d'OUT_COND, 0 dependance introuvable) ; simulation de resolution `ELK_HOST` : le nouveau job tombe bien derriere `WAZ_PURGE_MANUAL_GATE`, aux cotes des 4 autres purges deja connues (jamais un nouveau blocage inattendu ailleurs dans la chaine).

**Limite honnete** : jamais execute en conditions reelles a l'instant de cette entree (nouveau job) - a tester avec au moins un index hors-wazuh reellement present, en verifiant `_cat/indices` avant/apres pour confirmer que seule la famille `wazuh-*` survit.
## 2026-09-13 (suite) - `bin/order.sh` refuse une confirmation retapee a l'identique : meme bug de \r invisible que MNT_reinstall.sh, corrige plus largement

**Echec reel** : en testant le scenario BEAC sur VM1, `$APP_BIN/order.sh LS_024 "..."` a demande de retaper `LS_024` pour confirmer - fait, a l'identique - et a quand meme repondu "Confirmation incorrecte. Forcage annule, rien n'a ete execute." Exactement le meme symptome que l'incident deja corrige sur `setup/MNT_reinstall.sh` (confirmation "oui" refusee malgre une saisie correcte).

**Cause reelle, deja identifiee une fois** : un retour chariot invisible (`\r`, introduit par certains clients terminal) peut se glisser dans la valeur lue par `read`, rendant la comparaison stricte `[ "$CONFIRM" != "$JOB_ID" ]` fausse a l'octet pres sans que rien ne le laisse voir a l'ecran.

**Corrige plus largement que le seul point d'echec observe** : recherche systematique de tout le meme motif (`read -r -p ... CONFIRM`) dans `bin/` et `setup/` plutot que de ne corriger que `order.sh` - trouve aussi dans `bin/confirm.sh` (jamais rencontre en echec reel a ce jour, mais strictement le meme code, donc la meme vulnerabilite latente). Les deux nettoient desormais `$CONFIRM` (`"${CONFIRM%$'\r'}"`) avant comparaison, meme correctif que `MNT_reinstall.sh`.

**Verifie** : `bash -n` propre sur les 2 fichiers.

**A faire sur VM1** : `git pull origin main` (ce correctif vit sur `main`, independant de la branche `demo-donnees-realistes` en cours de test), puis reessayer `$APP_BIN/order.sh LS_024 "..."`.

**Limite honnete** : cause exacte du `\r` (client PuTTY ? copier-coller ? terminal specifique ?) jamais formellement identifiee - le correctif protege contre le symptome de facon robuste quelle que soit la cause exacte, sans la diagnostiquer plus avant.

## 2026-09-14 (suite) - REPEATABLE_JOBS inoperant au premier essai : ordre auto-sync/source corrige

**Constat reel** : `REPEATABLE_JOBS` ajoute plus tot ce soir (voir entree precedente) ne fonctionnait pas pour `BEAC_002`/`BEAC_003` - `order.sh` continuait d'afficher "deja fait, rien a forcer" malgre le nouveau `vars.conf` deja pousse sur GitHub. `BEAC_001` avait fonctionne, mais par coincidence : il n'avait jamais tourne avant sur cette VM (aucun marqueur `.ok` preexistant a effacer), donc son succes ne prouvait rien sur le mecanisme lui-meme.

**Cause reelle** : le bloc de synchronisation automatique (ajoute juste avant, meme soiree) avait ete place APRES `source "$VARS_FILE"` dans `bin/order.sh` ET `orchestrator.sh`. Au tout premier lancement suivant une mise a jour, le script chargeait donc encore l'ANCIEN `vars.conf` (sans `REPEATABLE_JOBS`) en memoire, PUIS synchronisait le depot (mettant a jour `vars.conf` sur disque pour le lancement SUIVANT, jamais celui-ci) - aucune erreur ne le signalait, le symptome ressemblait a un simple oubli de synchronisation.

**Corrige** : bloc de synchronisation deplace AVANT tout `source`, dans les deux fichiers - `vars.conf` fraichement recupere est desormais TOUJOURS celui reellement charge par l'execution qui vient de le recuperer, plus jamais un second essai necessaire.

**Verifie** : `bash -n` propre sur les 2 fichiers ; simulation reelle (job factice, marqueur preexistant) confirmant l'effacement automatique du `.ok` avant relance.

## 2026-09-14 (suite) - Volume aligne a 100 enregistrements par index

**Demande explicite** : "les jobs doivent remplir 100 enregistrement par index". `BEAC_002` (CyrielleMoney) etait deja a 100 par defaut (`WAZ_DEMO_SEED_COUNT:-100`, jamais modifie). `LCBFT_DEMO_BULK_COUNT` (`BEAC_003`, demo publique LCB-FT) passe de 50 a 100 pour le meme volume des deux cotes - `BEAC_001` (scenario "realiste", 1 a 5 enregistrements aleatoires) volontairement INCHANGE, sa variabilite etant le but explicite de sa creation ("montrer qu'on peut detecter 1 enregistrement et a certains moments voir meme 5 d'un coup") - a confirmer aupres de l'operateur si ce n'est pas ce qui etait vise.

**Consequence honnete** : `BEAC_003` dure desormais environ 3min20 (100 x 2s) au lieu d'1min40.

## 2026-09-16 - 4 nouveaux playbooks de detection/reponse (Rootcheck, auditd, VirusTotal, IOC)

**Demande explicite** : construire un job "RUN" pour chacun de 4 cas d'usage Wazuh standards discutes via un classeur playbook prealable (feuille Excel, catalogue + flux detaille + suivi) : detection de rootkit/malware (Rootcheck), audit des commandes systeme (auditd), integration VirusTotal, et Threat Intelligence/IOC matching.

**Corrige (4 nouveaux jobs)** :
- **`jobs/WAG_007_ROOTCHECK.sh`** (`AGENT_HOST`, `IN_COND=WAG_READY`, `OUT_COND=WAG_ROOTCHECK_OK`) : le module Rootcheck est deja livre actif par le paquet wazuh-agent (frequence vendor 43200s/12h, trop lent pour une demo) - ce job ne le desactive jamais, il garantit son activation explicite et resserre uniquement la frequence (`WAZ_ROOTCHECK_FREQUENCY_SEC`, vars.conf, defaut 300s).
- **`jobs/WAG_008_AUDITD_INTEGRATION.sh`** (`AGENT_HOST`, `IN_COND=WAG_READY`, `OUT_COND=WAG_AUDITD_OK`) : installe `auditd`, ajoute une regle d'audit sur les executions de commandes (`execve`), fait lire `/var/log/audit/audit.log` par l'agent Wazuh.
- **`jobs/WAZ_050_VIRUSTOTAL_INTEGRATION.sh`** (`ELK_HOST`, **manuel uniquement**, `IN_COND=VIRUSTOTAL_MANUAL_GATE` jamais satisfaite ailleurs, `OUT_COND=WAZ_VT_INTEGRATION_OK`) : necessite une cle API VirusTotal gratuite creee par l'operateur lui-meme (jamais generee ici), deposee dans `secrets/virustotal_api_key.txt` (meme principe que `SMTP_PASS_FILE`, jamais dans vars.conf/Git). Manuel car une dependance externe non garantie sur toute machine ne doit jamais bloquer une chaine `ALWAYS` normale (lecon deja appliquee ailleurs dans ce projet) - configure aussi un dossier FIM temps reel dedie (`VT_WATCH_DIR`) pour avoir quelque chose a soumettre.
- **`jobs/WAZ_051_IOC_CDB_LIST.sh`** (`ELK_HOST`, `ALWAYS`, `IN_COND=WAZ_MANAGER_UP`, `OUT_COND=WAZ_IOC_LIST_OK`) : liste CDB locale de hashes MD5 malveillants connus (`IOC_MD5_BLOCKLIST`, vars.conf, meme principe de liste configurable que `SKIP_JOBS`/`ES_DEMO_INDEX_PREFIXES` - pre-remplie avec le hash public du fichier de test EICAR, jamais un vrai malware), correlee a chaque evenement FIM via une regle dediee (id 100200) ajoutee a `local_rules.xml`. Aucune dependance externe (contrairement a VirusTotal) - reste donc `ALWAYS`, jamais bloquant.

**Erreur trouvee et corrigee en cours de route** : virgule non protegee dans la description de `WAZ_050` ("...ELK_HOST, necessite...") - meme classe de bug de decalage de colonnes CSV deja rencontree plusieurs fois cette nuit, cette fois detectee immediatement par l'audit avant tout commit (jamais poussee).

**Verifie** : `bash -n` propre sur les 4 jobs + `vars.conf` ; bits executables corriges ; audit CSV complet (291 lignes, 0 doublon, 0 ligne malformee, 0 dependance introuvable) ; simulation de resolution par vagues : `ELK_HOST` 220/232 (nouveau bloque = uniquement `WAZ_050`, attendu puisque manuel ; aucun autre nouveau blocage), `AGENT_HOST` 53/56 (aucun nouveau blocage, les 3 bloques restants sont les `BEAC_00x` deja connus) ; `WAG_ROOTCHECK_OK`/`WAG_AUDITD_OK`/`WAZ_IOC_LIST_OK` se resolvent tous automatiquement.

**Limite honnete** : aucun des 4 jobs n'a ete teste en conditions reelles a l'instant de cette entree (nouveaux jobs, jamais executes sur les VMs). Pour `WAZ_050`/VirusTotal specifiquement, la cle API doit etre creee et deposee manuellement avant le premier essai - sans elle, le job refuse proprement plutot que d'echouer de facon confuse plus loin.

## 2026-09-16 (suite) - Teste en reel : succes chez l'etudiante, 3 causes reelles trouvees et corrigees chez l'operateur

**Confirme en reel, cote etudiante** : chaine complete PB-007 fonctionnelle de bout en bout du premier coup - depot du fichier EICAR dans `VT_WATCH_DIR` -> alerte FIM -> soumission VirusTotal -> alerte enrichie reelle visible dans Wazuh Dashboard/Threat Hunting : `"VirusTotal: Alert - /root/wef_vt_watch/eicar.txt - 66 engines detected this file"` (rule.id 87105, niveau 12).

**Cote operateur, meme test, echec silencieux - diagnostic mene entierement par elimination sur preuve reelle (jamais une supposition acceptee sans verification) :**
1. `integrations.log` vide (0 octet, date anterieure au test) -> le processus `wazuh-integratord` n'a jamais ete declenche.
2. `ps aux` + `journalctl` : `wazuh-integratord` tourne bien, `Enabling integration for: 'virustotal'` confirme - l'integration EST chargee.
3. `alerts.log` : les evenements FIM (`File '...' added`) existent bien - le FIM fonctionne.
4. **Cause reelle trouvee dans le JSON brut de l'alerte** (`alerts.json`) : l'evenement passe par la regle **preexistante `id="100100"`** (`jobs/WAZ_025.sh`, "Modification detectee sur un fichier surveille de la Forge" - regle generique deja en place, ajoutee bien avant ce soir pour un autre usage, jamais con,cue pour prevoir un futur filtre par groupe). Cette regle n'expose que `"groups":["local","syslog","sshd"]` (heritage du bloc generique de `local_rules.xml`), JAMAIS `"syscheck"` - le filtre `<group>syscheck</group>` de `WAZ_050` ne matchait donc jamais, sans la moindre erreur visible nulle part (integratord n'a meme pas de raison de se plaindre : il ne voit simplement jamais l'alerte).

**Corrige (`jobs/WAZ_050_VIRUSTOTAL_INTEGRATION.sh`)** : filtre desormais par `<rule_id>100100,550,553,554</rule_id>` (la regle qui se declenche reellement ici, plus les regles FIM standard pour rester correct sur un futur chemin non intercepte par la regle 100100) - jamais par `<group>`, trop fragile en presence d'une regle locale plus specifique qui absorbe l'evenement en premier. Jamais touche `WAZ_025.sh` lui-meme (regle utile ailleurs, hors de portee de ce correctif).

**Incident de securite mineur, traite en direct** : une cle API VirusTotal reelle a ete collee en clair dans la conversation par erreur - traitee immediatement comme compromise (consigne de la regenerer sur virustotal.com), jamais reutilisee dans un correctif ni stockee par l'assistant.

**Verifie** : `bash -n` propre. Test reel complet a refaire cote operateur avec la regle corrigee + la cle regeneree (non encore confirme a l'instant de cette entree).

## 2026-09-16 (suite) - Confirme en reel des les deux cotes + correctif applique par anticipation sur WAZ_051

**Confirme en reel, cote operateur cette fois** : `rule_id` fonctionne - alerte VirusTotal reelle obtenue (`"VirusTotal: Alert - .../eicar_test4.txt - 65 engines detected this file"`, rule.id 87105, level 12, 65/67 moteurs positifs) en ~3s apres l'alerte FIM. PB-007 valide des les deux VMs desormais (etudiante + operateur), avec la meme regle 87105 des deux cotes.

**Correctif applique PAR ANTICIPATION sur `jobs/WAZ_051_IOC_CDB_LIST.sh`** (demande explicite : "mettez a niveau tout sur github pour qu'on n'ait plus jamais ce souci") : la regle 100200 (liste IOC) utilisait le meme `<if_group>syscheck</if_group>` qui venait de se reveler defaillant sur WAZ_050 - jamais teste en reel a ce jour, mais la cause racine etant desormais confirmee (regle preexistante `WAZ_025`/id 100100 capte tout evenement FIM en premier, n'expose jamais le groupe "syscheck"), corrige AVANT qu'elle ne soit decouverte une seconde fois de la meme facon. Chaine desormais sur `<if_sid>100100,550,553,554</if_sid>` - meme principe que le correctif de `WAZ_050`.

**Verifie** : `bash -n` propre. Non encore reteste en conditions reelles a l'instant de cette entree (la config precedente de `WAZ_051` avait pourtant reussi a s'appliquer sans erreur - seule la regle interne change, un simple rejeu du job suffit).

## 2026-09-16 (suite) - Confirme en reel : VirusTotal se declenche via les regles standard (550/554), pas seulement 100100

**Confirme en reel** : test live (`eicar_live.txt`) - 2 evenements FIM distincts sur le meme fichier ("File added" -> rule 554, puis "Integrity checksum changed" -> rule 550, ~4 minutes plus tard), CHACUN a correctement declenche une alerte VirusTotal distincte (49 puis 64 moteurs positifs). Confirme que le filtre combine `rule_id=100100,550,553,554` (WAZ_050) etait le bon choix : selon l'evenement, c'est tantot la regle locale 100100, tantot une regle standard qui "gagne" - jamais un comportement garanti a l'avance, la couverture des deux etait necessaire.

## 2026-09-16 (suite) - Nouveau job : surveillance whodata de /etc/ssh/sshd_config

**Demande explicite** : "modifions le fichier de config du SSH... je veux qu'on dise qu'on a modifie ce fichier et par qui" - surveillance FIM avec attribution d'auteur (utilisateur/PID/processus reel), pas seulement "quelque chose a change".

**Corrige (`jobs/WAZ_052_SSHD_CONFIG_WHODATA.sh`, `ELK_HOST`, `ALWAYS`, `IN_COND=WAZ_MANAGER_UP`, `OUT_COND=WAZ_SSHD_WHODATA_OK`)** : installe `auditd` (requis par le mode `whodata` de Wazuh sous Linux - Wazuh gere lui-meme les regles audit necessaires une fois whodata active, aucune regle manuelle a poser), ajoute `<directories whodata="yes" check_all="yes">/etc/ssh/sshd_config</directories>` - portee volontairement etroite (ce seul fichier, jamais tout `/etc/ssh/`). Meme motif chattr deja etabli (WAZ_050/051) pour `ossec.conf` deja verrouille par `WAZ_032`.

**Verifie** : `bash -n` propre ; bit executable corrige ; audit CSV complet (292 lignes, 0 doublon). Jamais teste en conditions reelles a l'instant de cette entree.

## 2026-09-17 - Nouveau job : illustrer une menace venant de VM2 (pas seulement d'ELK_HOST)

**Demande explicite** : "maintenant si la menace vient de VM2 ? illustrons" - jusqu'ici, tous les tests VirusTotal/IOC (EICAR, curl, fichier jamais-vu) avaient ete deposes directement sur `ELK_HOST`, surveilles par l'agent integre du manager lui-meme (`wef-elk-core`, id 000) - jamais depuis un vrai `AGENT_HOST` distant.

**Ajoute (`jobs/WAG_009_VT_WATCH_DIR.sh`, `AGENT_HOST`, `WAZUH_AGENT`, `IN_COND=WAG_READY`, `OUT_COND=WAG_VT_WATCH_OK`)** : ouvre le meme dossier surveille `VT_WATCH_DIR` (vars.conf), mais cote agent - dans le propre `ossec.conf` de VM2, jamais celui du manager. Verifie avant ecriture que le verrou `chattr +i` de `WAZ_032` ne s'applique jamais aux agents (job `ELK_HOST` uniquement, `jobs_table.csv:242`) - pas de deverrouillage/reverrouillage necessaire ici, contrairement a `WAZ_050`/`WAZ_051`/`WAZ_052`.

**Aucune modification cote `ELK_HOST`** : l'integration VirusTotal de `WAZ_050` filtre par `rule_id` (100100,550,553,554), jamais par agent - un evenement FIM remonte par N'IMPORTE QUEL agent enregistre declenche la meme regle, donc la meme soumission automatique a VirusTotal. La preuve attendue en conditions reelles : l'alerte generee portera le nom de l'agent VM2 (`AGENT_NAME`, vars.conf : `vm2-beats-wazuh-agent`) au lieu de `wef-elk-core`, visible immediatement dans le donut "Top 5 agents" du Dashboard filtre `rule.groups: virustotal`.

**Verifie** : `bash -n` propre ; audit CSV complet (294 lignes, 0 doublon `OUT_COND`, 0 colonne malformee). Jamais teste en conditions reelles a l'instant de cette entree - a confirmer via `bin/order.sh` sur VM2 (WAG_009_VT_WATCH_DIR) puis depot d'un fichier EICAR dans le dossier surveille.

## 2026-09-18 - VirusTotal detecte seul, sans depot manuel : elargissement de la surveillance FIM

**Demande explicite** : "je veux que virustotal detecte seul des fichiers sans qu'un humain lui fournisse le fichier, c'est possible ca?" - puis, apres proposition d'options : "tout le disque depuis la racine / mais qu'il renvoit les vrai probleme de grace et non qu'il cree les alertes partout et partout de meme sur le poste des clients" - puis, apres explication des limites reelles de "/" en temps reel : "faisons comme vous percevez svp".

**Refuse (justifie, jamais simplement "impossible")** : surveiller `/` entier en `realtime` n'est pas fait, pour 3 raisons verifiables et non une simple prudence : (1) le nombre de "watches" `inotify` du noyau est limite (quelques centaines de milliers) - depasse en quelques secondes sur `/`, Wazuh arrete alors de surveiller SANS erreur visible ; (2) le volume d'ecritures purement internes au systeme (logs, cache dnf, fichiers temporaires) saturerait en quelques secondes l'API VirusTotal gratuite (4 requetes/minute), noyant les vraies alertes dans le bruit - l'inverse exact de la demande ; (3) un attaquant reel ecrit rarement dans `/usr/lib` ou `/var/cache`, mais la ou un humain peut ecrire.

**Corrige (`jobs/WAZ_050_VIRUSTOTAL_INTEGRATION.sh` sur `ELK_HOST`, `jobs/WAG_009_VT_WATCH_DIR.sh` sur `AGENT_HOST`)** : la surveillance FIM passe d'un unique dossier de demo (`VT_WATCH_DIR`) a une liste construite dynamiquement A CHAQUE EXECUTION (jamais devinee a l'avance, seuls les dossiers reellement presents sur la machine sont inclus) : `/root`, `/tmp`, les vrais dossiers `/home/*` presents, les points de montage `/media` et `/mnt` (crees s'ils sont absents, pour capter une cle USB montee plus tard - le FIM `realtime` de Wazuh detecte les nouveaux sous-dossiers qui y apparaissent), plus le dossier de demo lui-meme. Explicitement exclu : `/proc`, `/sys`, `/dev`, `/var/log`, `/var/cache`, `/var/lib`, `/var/ossec` (pour eviter que Wazuh ne s'auto-declenche sur ses propres ecritures).

**Verifie** : `bash -n` propre sur les deux fichiers. Jamais teste en conditions reelles a l'instant de cette entree - a confirmer en rejouant `WAZ_050`/`WAG_009_VT_WATCH_DIR` (idempotents, le bloc FIM precedent est retire puis reecrit) puis en deposant un fichier EICAR dans un dossier `/home/<utilisateur>` reel (jamais teste jusqu'ici, seul `/root/wef_vt_watch` avait ete confirme).

**Confirme en reel cote `ELK_HOST`** : `WAZ_050` elargi fonctionne (rejoue avec succes apres suppression du marqueur `.ok`, dossiers construits dynamiquement bien pris en compte).

**Incident reel cote `wef-beats-sensor` (VM2, AGENT_HOST)** : `WAG_009_VT_WATCH_DIR` echoue avec "Operation non permise" sur `/var/ossec/etc/ossec.conf`. Contredit directement l'hypothese ecrite dans le commentaire d'en-tete du job ("l'agent n'est jamais verrouille par chattr, `WAZ_032` est `ELK_HOST` uniquement, jamais applique ici") - hypothese jamais verifiee sur cette VM precise avant d'etre ecrite, cause exacte encore non confirmee a l'instant de cette entree (a diagnostiquer : `lsattr`, `ROLE` effectif de cette VM dans `vars.local.conf`, historique reel d'execution de `WAZ_032` sur cette machine via `bin/history.sh`).

**Corrige (`jobs/WAG_009_VT_WATCH_DIR.sh`)** : ajout du meme motif defensif deja etabli sur `WAZ_050`/`051`/`052` - detection `lsattr` avant ecriture, `chattr -i` temporaire si necessaire, ecriture, puis reverrouillage (droits + `chattr +i`) **uniquement si le fichier etait deja immuable au depart** (jamais introduit un nouveau verrou qui n'existait pas avant sur un agent - contrairement a `WAZ_050` qui, lui, verrouille systematiquement en sortie car `ELK_HOST` doit toujours finir verrouille par convention du projet). Corrige pour fonctionner que le fichier soit verrouille ou non, sans attendre d'avoir confirme la cause racine.

**Diagnostic reel confirme** (`lsattr`/`ROLE`/`bin/history.sh WAZ_032`, tous colles par l'operateur) : `WAZ_032` n'a **jamais** tourne sur `wef-beats-sensor` (historique vide) et `ROLE="AGENT_HOST"` dans `vars.local.conf` prime correctement sur le `ROLE=ELK_HOST` par defaut de `vars.conf` (partage par git). Donc la cause du verrou n'est PAS un bug de resolution de role WEF - elle reste non confirmee avec certitude (hypothese la plus probable : l'attribut `chattr`, un bit du systeme de fichiers, aurait ete copie tel quel si le disque de VM2 a ete clone/cree a partir d'une image ou `ossec.conf` etait deja verrouille). Rejoue avec succes des les deux VM apres le correctif (`FORCE_OK` dans l'historique des deux cotes).

## 2026-09-18 (suite) - Nouveau : sonde permanente pour les nouveaux comptes utilisateurs

**Demande explicite** : "un job sonde devrait verifier dans /home/* si un utilisateur a ete cree et l'ajouter au job qui a la connaissance des repertoires a surveiller par virus total - sinon a quoi sert donc l'orchestration si ce n'est pas pour ce genre de choses".

**Precision architecturale donnee en reponse** : `orchestrator.sh` resout un graphe de dependances en plusieurs passes POUR UNE INSTALLATION - jamais une tache de fond continue. Un compte cree apres le dernier passage ne serait jamais revu sans relancer manuellement `WAZ_050`/`WAG_009`. Le vrai mecanisme deja existant dans ce projet pour ce genre de derive continue est le motif "guardian" (timer systemd independant), deja etabli par `jobs/INFRA_004_HEALTH_GUARDIAN.sh` - reutilise a l'identique, jamais reinvente.

**Ajoute (`jobs/WAZ_053_VT_WATCH_GUARDIAN.sh` sur `ELK_HOST`, `jobs/WAG_010_VT_WATCH_GUARDIAN.sh` sur `AGENT_HOST`, `IN_COND` sur la condition de surveillance deja active, `OUT_COND=*_VT_WATCH_GUARDIAN_OK`)** : installe un script de controle (`/usr/local/sbin/wef-vt-watch-guardian.sh`) + un timer systemd (`wef-vt-watch-guardian.timer`, toutes les 10 minutes) qui reconstruit la meme liste de dossiers que `WAZ_050`/`WAG_009` et la compare a celle actuellement ecrite dans `ossec.conf` - ne touche RIEN si identique (jamais verbeux en fonctionnement normal, meme discipline que `INFRA_004`), et si un ecart reel est trouve (nouveau `/home/<utilisateur>`), reecrit uniquement la ligne `<directories>` (jamais le bloc integration/cle API), gere le verrou `chattr` de la meme facon defensive que `WAG_009` corrige plus haut, et redemarre le service concerne.

**Verifie reellement (pas juste relu)** : la logique de decouverte/comparaison a ete extraite du heredoc et executee directement en bash (`bash -n` ne valide PAS le contenu d'un heredoc, seulement le script qui le contient) - confirme qu'un nouveau dossier simule est correctement detecte comme un ecart, et que la reecriture `sed` produit bien la ligne attendue, verifiee par `grep -qF` apres coup. `bash -n` propre sur les deux fichiers de job. Jamais teste en conditions reelles sur une VM (timer + creation reelle d'un compte utilisateur) a l'instant de cette entree.

## 2026-09-18 (suite) - Systeme de calendrier natif : l'orchestrateur decide, jamais un job qui s'auto-planifie

**Demande explicite, revenant sur le point precedent** : "je crois que je me suis trompé d'instructions à vous donner. En fait l'orchestrateur doit intégrer un systeme de calendrier pour savoir quel jour à quel heure quel minute quel frequence lancer certains job... ce ne sera plus le job qui appelle l'orchestrateur mais c'est l'orchestrateur qui sait selon les politiques comment jouer les jobs". Objectif final precise dans la meme discussion : "je veux construire l'image de toute la suite control M de BMC" - `IN_COND`/`OUT_COND` est deja l'analogue WEF du modele de conditions Control-M ; il manquait l'equivalent du moteur de calendrier.

**Plan ecrit et valide avant tout code** (voir l'historique de planification) : deux faits reels verifies par lecture directe du code avant de concevoir quoi que ce soit - (1) aucun mecanisme periodique n'existe pour l'orchestrateur lui-meme (`setup/svc_orch.sh` installe un `.service` sans aucun `.timer`), (2) recherche globale `flock|.lock|LOCK_FILE|lockfile` dans tout le depot = zero resultat, aucun verrou n'a jamais ete necessaire jusqu'ici.

**Piege identifie et EVITE avant d'ecrire une seule ligne** (relecture croisee par un second agent pendant la conception) : ajouter une 9e colonne a `jobs_table.csv` aurait casse silencieusement les 5 parseurs `IFS=','` existants (la derniere variable lue, `OUT_COND`, aurait avale le reste de la ligne) - corrige par conception, jamais par correctif apres coup : nouveau fichier separe `schedules.csv` (`JOB_ID,SCHEDULE,ENABLED`), zero impact sur `jobs_table.csv`.

**Construit (Etape 1 du plan - le moteur seul, avant toute migration des jobs existants)** :
- `lib/run_job.sh` (nouveau) : extrait le bloc lancement/attente/marqueur `.ok`/ligne d'historique, avant duplique a l'identique entre `orchestrator.sh` et `bin/order.sh`. `orchestrator.sh` et `bin/order.sh` modifies pour l'appeler (comportement inchange - `bash -n` + relecture ligne a ligne confirment ; seul detail cosmetique deliberement simplifie : le suffixe " (FORCE)" du marqueur EN_COURS de `order.sh` apparait desormais aussi dans la ligne d'historique, jamais un souci puisque le label `FORCE_OK`/`FORCE_ECHEC` reste la vraie preuve d'audit).
- `lib/lock.sh` (nouveau) : verrou `flock` sur `state/.wef_run.lock` + sidecar `state/.wef_run.owner` (identite, puisque `flock` n'en porte aucune) + bypass `WEF_LOCK_HELD` pour eviter un auto-blocage. Integre a `orchestrator.sh` (attente 10s) et `bin/order.sh` (attente 5s, prise APRES la confirmation tapee - jamais pendant qu'un humain reflechit au prompt).
- `lib/cron_match.sh` (nouveau) : comparateur d'expression cron a 5 champs (`*`, entier, `*/N` uniquement - listes/plages hors perimetre, limite documentee). Fonctionne comme un vrai `crond` : teste "est-ce que MAINTENANT correspond ?", ne calcule jamais de prochaine echeance - un tick manque est reellement manque, jamais rattrape.
- `bin/scheduler.sh` (nouveau) : tick toutes les 60s, lit `schedules.csv`, verifie le coupe-circuit `SCHEDULER_ENABLED` (`vars.conf`) EN PREMIER, respecte `HELD`/`SKIP_JOBS` comme l'orchestrateur normal, et avertit (sans bloquer) si un job planifie alimente par erreur le graphe de dependances (`OUT_COND` consomme par un `IN_COND` ailleurs - `NONE` explicitement exclu de cette verification, voir bug reel ci-dessous).
- `jobs/INFRA_010_SCHEDULER_INSTALL.sh` (nouveau, `ROLE=ALL`) : installe le timer systemd unique (`wef-scheduler.timer`/`.service`), meme motif deja PROUVE par `setup/svc_orch.sh` (unite generee par heredoc, `ExecStart` pointant directement sur `bin/scheduler.sh` DANS le depot - jamais une copie figee ailleurs, contrairement au motif `WAZ_053`/`INFRA_004` : un futur `git pull` corrigeant `bin/scheduler.sh` prend effet au tick suivant, sans jamais rejouer ce job).
- `bin/audit.sh`/`bin/history.sh` : reconnaissent desormais `SCHEDULED_OK`/`SCHEDULED_ECHEC` dans les totaux OK/ECHEC (sinon une execution planifiee aurait ete invisible des deux statistiques, silencieusement).

**Bug reel trouve PAR le test fonctionnel, jamais a la simple relecture** : le garde-fou "job planifie qui alimente le graphe de dependances" declenchait une fausse alerte systematique, car `OUT_COND=NONE` (le sentinel projet pour "aucune dependance", utilise par des dizaines de jobs) etait traite comme une vraie condition - n'importe quel job planifie (qui utilise `OUT_COND=NONE` par construction) se voyait donc signale comme "consomme par" tout autre job dont `IN_COND=NONE`. Corrige : `NONE` explicitement exclu de la verification.

**Verifie reellement (jamais juste relu)** :
- `run_job()` : execute avec un vrai job qui reussit et un vrai job qui echoue (harnais `/tmp`) - en-tete pre-existant du log preserve (`>>`, jamais ecrase), `.ok` ecrit seulement en succes, marqueur EN_COURS nettoye, ligne d'historique correcte dans les deux cas.
- `lib/cron_match.sh` : 16 cas reels avec des tuples (minute,heure,jour,mois,jour_semaine) synthetiques, incluant le piege d'octal bash (`07`/`08`/`09`), l'indexation a 1 de `*/N` sur jour_mois/mois, l'alias dimanche `0`/`7`, et le refus explicite dom+dow simultanes - 16/16 reussis.
- `lib/lock.sh` : le bypass `WEF_LOCK_HELD=1` confirme fonctionnel sans jamais appeler `flock`. La contention reelle entre process (`flock -n` vs `flock -w`) n'a PAS pu etre testee dans cet environnement (Windows Git Bash - `flock` est un utilitaire Linux absent ici, confirme par `command -v flock` avant de conclure quoi que ce soit) - **limite honnete, a confirmer sur la VM reelle** (Oracle Linux 8.10, `flock` present par defaut).
- `bin/scheduler.sh` : harnais complet dans `/tmp` (faux `jobs_table.csv`/`schedules.csv`/job) avec stubs locaux pour `flock`/`logger` (absents de Git Bash Windows) - confirme qu'un job du declenche une fois, qu'un second tick dans LA MEME minute ne re-declenche PAS (anti-double-tir via `.lastmin`), qu'un job `ENABLED=0` ne tourne jamais, et que `SCHEDULER_ENABLED=0` bloque tout avant meme de lire `schedules.csv`.
- Audit standard `jobs_table.csv` (297 lignes, 0 doublon `OUT_COND`, 0 colonne malformee) + nouvel audit `schedules.csv` (aucune reference a un `JOB_ID` inconnu).

**Limite honnete a documenter** : la contention reelle du verrou `flock` entre plusieurs process sur systemd/Linux reste a confirmer sur VM1/VM2 (voir plan de verification) - la logique bash autour (bypass, sidecar d'identite, integration aux 3 points d'entree) est prouvee, l'appel a l'utilitaire systeme lui-meme ne l'est pas encore dans cet environnement.

**Etape 2 (migration de `WAZ_053`/`WAG_010` vers ce systeme) volontairement PAS faite maintenant** - le plan explicite de la faire seulement une fois l'Etape 1 confirmee en reel sur les deux VM.
