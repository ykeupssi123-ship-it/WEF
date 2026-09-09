# WAZ_ELK_FACTORY

**Un SIEM complet (Wazuh + pile ELK), installé et exploité par un
orchestrateur de jobs dans l'esprit de BMC Control-M.**

Ce dépôt contient tout ce qu'il faut pour déployer, sur un jeu de
machines virtuelles, une plateforme de détection et de supervision de
sécurité prête à l'emploi : Wazuh (agents, détection, tableau de bord
natif) + Elasticsearch / Logstash / Kibana (pile ELK classique) — les
deux backends alimentés par le même pipeline d'alertes, avec une bascule
réversible entre eux à la demande (exploitation).

Aucune installation manuelle service par service : un seul orchestrateur
lit une table de jobs (`jobs_table.csv`) et exécute chaque étape dans le
bon ordre, avec reprise automatique en cas d'échec.

## Pourquoi

Ce projet reproduit délibérément le vocabulaire et les réflexes d'un
outil d'ordonnancement de production (Control-M/Autosys) : chaque action
d'installation ou d'exploitation est un **job** identifiable, avec des
conditions d'entrée/sortie, un historique complet, et des opérations
standard (Force Run, Hold/Release, Set to OK, View History...) — voir la
feuille *Correspondance Control-M* du classeur d'exploitation.

## Démarrage rapide

1. Lisez [`docs/GUIDE_EXPLOITATION.md`](docs/GUIDE_EXPLOITATION.md) —
   machine par machine, étape par étape.
2. Ouvrez [`docs/TABLEAU_DE_BORD_EXPLOITATION.xlsx`](docs/TABLEAU_DE_BORD_EXPLOITATION.xlsx)
   — votre feuille de route pour piloter l'exploitation au quotidien
   (commandes prêtes à copier-coller, correspondance Control-M, scénarios
   de démonstration).
3. Sur VM1 :
   ```bash
   chmod +x *.sh bin/*.sh setup/*.sh jobs/*.sh
   ./orchestrator.sh
   ```

## Opérations d'exploitation (façon Control-M)

Racine minimale — `orchestrator.sh` reste le seul point d'entrée à la
racine. Toutes les actions d'exploitation vivent dans `bin/`, sous le
vrai nom de l'action Control-M correspondante (jamais une paraphrase
française) :

| Action Control-M | Commande |
|---|---|
| Hold | `./bin/hold.sh <JOB_ID> "<raison>"` |
| Free / Release | `./bin/free.sh <JOB_ID>` |
| Order / Force | `./bin/order.sh <JOB_ID> "<raison>"` |
| Set to OK | `./bin/confirm.sh <JOB_ID> "<raison>"` |
| View History | `./bin/history.sh <JOB_ID>` |
| Monitoring | `./bin/monitor.sh` |
| Tableau de bord final (URLs/logins/scenarios) | `./bin/summary.sh` |

### Depuis n'importe quel répertoire (`$APP_BIN`)

Une seule fois par machine (root) :
```bash
sudo setup/installer_env_cli.sh
```
Ouvre une nouvelle session (ou `source /etc/profile.d/wef-app-env.sh`),
et les variables `APP_HOME`/`APP_BIN`/`APP_CONF`/`APP_INF` sont
disponibles dans toute session CLI, peu importe le répertoire courant :

```bash
$APP_BIN/order.sh <JOB_ID> "<raison>"
$APP_BIN/hold.sh <JOB_ID> "<raison>"
$APP_BIN/monitor.sh
```

`APP_BIN` = `bin/` (les 12 outils d'action), `APP_CONF` = racine du
projet (`vars.conf`, `jobs_table.csv`, `secrets/`), `APP_INF` = `setup/`
(installateurs ponctuels). Relancez `setup/installer_env_cli.sh` après
tout déplacement/re-clonage du dépôt sur une nouvelle machine.

## Topologie recommandée

| Machine | Rôle | IP | Contenu |
|---|---|---|---|
| VM1 | `ELK_HOST` | `192.168.50.128` | PKI, Elasticsearch, Logstash, Kibana, Wazuh (manager, indexer, dashboard) |
| VM2 | `AGENT_HOST` | `192.168.50.130` | Agent Wazuh + Filebeat + Metricbeat |

Conservez ces adresses pour un déploiement sans friction (voir
`GUIDE_EXPLOITATION.md` pour le détail et la marche à suivre si vous
devez en changer).

## Ce que vous obtenez

- **Détection & réponse** : Wazuh (agents Linux/Windows, règles, alertes)
- **Recherche & visualisation** : deux tableaux de bord au choix, jamais
  les deux à la fois — Wazuh Dashboard (natif) ou Kibana (ELK classique),
  bascule réversible à la demande (`WAZ_035_MODE_CONVERGENT` /
  `WAZ_039_MODE_SOUVERAIN` — voir le classeur d'exploitation)
- **PKI interne** générée automatiquement (ou raccordable à une PKI
  d'entreprise existante — `PKI_MODE=external`)
- **Supervision de l'exploitation elle-même** : tableau de bord web live
  (lecture seule) montrant l'état de chaque job, historique complet,
  alerte email sur échec (optionnel)
- **Auto-guérison documentée** : mots de passe désynchronisés, verrous
  disque plein, pipelines figés — chaque cas déjà rencontré a son job de
  correction rejouable à la demande

## Sécurité

- **Aucun secret n'est jamais écrit en dur dans le code ou versionné.**
  Tous les mots de passe sont générés à la première exécution et stockés
  individuellement dans `secrets/*.txt` (droits `600`, hors du dépôt —
  voir `.gitignore`).
- Chaque secret a un fichier dédié et une seule fonction autorisée à le
  lire/régénérer — jamais de copie qui traîne ailleurs.
- PKI TLS interne pour tous les flux inter-services.
- Voir [`secrets/README_SECRETS.txt`](secrets/README_SECRETS.txt) pour le
  détail exact de chaque fichier.

## Structure du dépôt

```
orchestrator.sh              orchestrateur principal (Linux) - SEUL script a la racine
jobs_table.csv                table des jobs (dépendances, description)
vars.conf                       toute la configuration (aucune valeur en dur ailleurs)
bin/                            actions d'exploitation Control-M (hold.sh, free.sh,
                                 order.sh, confirm.sh, history.sh, monitor.sh,
                                 notify.sh, profile.sh, audit.sh,
                                 reset_es_password.sh, resume.sh, summary.sh,
                                 dashboard.py)
setup/                          installation ponctuelle (svc_orch.sh, svc_dash.sh,
                                 installer_env_cli.sh) - jamais utilise au quotidien,
                                 seulement a la mise en place
jobs/                          les scripts, un par job (jobs/lib/ = fonctions partagées)
jobs_windows/                  kit PowerShell (agents Windows)
lib/                            fonctions communes à l'orchestrateur
templates/                      gabarits d'index (mappings Elasticsearch/OpenSearch)
maintenance/                    scripts d'entretien (purge, diagnostic)
secrets/                        secrets générés à l'exécution (vide au dépôt)
docs/GUIDE_EXPLOITATION.md     mode d'emploi complet
docs/TABLEAU_DE_BORD_EXPLOITATION.xlsx   classeur d'exploitation (commandes, Control-M)
docs/JOURNAL_TECHNIQUE.md      journal technique complet (optionnel, approfondi)
```

## Aller plus loin

Le journal technique complet ([`docs/JOURNAL_TECHNIQUE.md`](docs/JOURNAL_TECHNIQUE.md))
documente chaque bug réel rencontré pendant la construction de ce
projet — cause exacte, diagnostic, correctif, test de non-régression.
Lecture optionnelle, utile pour comprendre une décision d'architecture
ou pour toute modification future du code.
