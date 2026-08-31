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

1. Lisez [`GUIDE_EXPLOITATION.md`](GUIDE_EXPLOITATION.md) — machine par
   machine, étape par étape.
2. Ouvrez [`docs/TABLEAU_DE_BORD_EXPLOITATION.xlsx`](docs/TABLEAU_DE_BORD_EXPLOITATION.xlsx)
   — votre feuille de route pour piloter l'exploitation au quotidien
   (commandes prêtes à copier-coller, correspondance Control-M, scénarios
   de démonstration).
3. Sur VM1 :
   ```bash
   chmod +x orchestrator.sh jobs/*.sh
   ./orchestrator.sh
   ```

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
orchestrator.sh              orchestrateur principal (Linux)
jobs_table.csv                table des jobs (dépendances, description)
jobs/                          les scripts, un par job (jobs/lib/ = fonctions partagées)
jobs_windows/                  kit PowerShell (agents Windows)
lib/                            fonctions communes à l'orchestrateur
templates/                      gabarits d'index (mappings Elasticsearch/OpenSearch)
maintenance/                    scripts d'entretien (purge, diagnostic)
vars.conf                       toute la configuration (aucune valeur en dur ailleurs)
secrets/                        secrets générés à l'exécution (vide au dépôt)
GUIDE_EXPLOITATION.md          mode d'emploi complet
docs/TABLEAU_DE_BORD_EXPLOITATION.xlsx   classeur d'exploitation (commandes, Control-M)
docs/JOURNAL_TECHNIQUE.md      journal technique complet (optionnel, approfondi)
```

## Aller plus loin

Le journal technique complet ([`docs/JOURNAL_TECHNIQUE.md`](docs/JOURNAL_TECHNIQUE.md))
documente chaque bug réel rencontré pendant la construction de ce
projet — cause exacte, diagnostic, correctif, test de non-régression.
Lecture optionnelle, utile pour comprendre une décision d'architecture
ou pour toute modification future du code.
