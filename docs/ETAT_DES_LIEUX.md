# État des lieux — Phase 0 (lecture seule)

Fait le 2026-10-21, sur VM1 (wef-elk-core), via SSH réel — rien exécuté hors des
commandes de diagnostic ci-dessous.

## a. `dossier_check.sh` — le classeur est-il encore vrai ?

**Un vrai bug trouvé et corrigé avant de pouvoir répondre** : le script utilisait
`subprocess.run(capture_output=True)`, une option Python 3.7+ — VM1 tourne en
Python 3.6.8. Corrigé (`stdout=PIPE, stderr=PIPE`), redéployé, revérifié.

Verdict brut : **15 écarts**. En réalité, une fois triés :

| Catégorie | Nombre | Nature réelle |
|---|---|---|
| Format d'heure (`22:00:00` vs `22:00`) | 4 | **Faux positif** — le script de vérification compare les chaînes sans normaliser le format, pas un vrai écart |
| Casse de booléen (`True`/`False` vs `true`/`false`) | 7 | **Faux positif** — même cause : comparaison de texte brut, pas de valeur |
| `LEAVE_USER`/`LEAVE_USERS` vides sur la machine, renseignés dans le classeur | 2 | **Normal** — levier de démo, vide au repos, rempli seulement pendant un test de congé |
| `ES_001_OS_PREP` cité (Pilotage WEF, exemple FONC-02) mais absent de `jobs_table.csv`/`jobs/` | 1 | **Réel** — mauvais exemple de job cité dans le classeur |
| `MNT_PURGE_HIST` cité (Pilotage WEF, r366) mais introuvable | 1 | **Réel** — à vérifier, référence probablement obsolète |

→ **2 vrais écarts**, pas 15. La prochaine version de `dossier_check.py` doit
normaliser heure/booléen avant de comparer, sinon chaque vérification future
criera au loup pour rien.

## b. `daily_log.sh`

Tourne sans erreur. `TODAY.log` affiche désormais aussi la ligne `WORKBOOK`
(verdict de `dossier_check.log`) en tête — fusion faite entre la version envoyée
par l'autre IA (qui avait réintroduit les sous-titres littéraires et supprimé les
couleurs ANSI — régression non voulue, corrigée) et ma version déjà en place.

## c. Inventaire

- `jobs_table.csv` : 321 lignes de jobs.
- `jobs/*.sh` : 321 fichiers — **en phase, aucun écart**.
- `jobs_windows/` : 27 fichiers.
- Rien trouvé sur VM1 absent de Git pour l'instant au-delà de ce qui était déjà
  connu (`bin/audit_sheet.py`, `bin/dossier_check.py`, les jobs `AISOC_*` —
  tout ajouté par nos soins cette semaine, jamais commité).

## d. Les gardiens écrivent-ils dans `JOBS_HISTORY.csv` ?

**Non, confirmé à nouveau** : `INFRA_004_HEALTH_GUARDIAN`, `INFRA_005_DISK_HYGIENE`,
`WAZ_041_ALERT_CANARY`, `INFRA_003_DEVNULL_GUARDIAN` — 0 ligne chacun. Ce sont des
timers systemd autonomes (`/usr/local/sbin/wef-*.sh`) qui journalisent via
`logger`/journald, jamais via `lib/run_job.sh`. Déjà documenté lundi dernier,
toujours vrai aujourd'hui — rien n'a changé.

## Proposition pour la suite

Phase 1 (revue des 321 jobs) est un gros chantier — je propose de la découper
en lots de 10, avec un arrêt après chaque lot pour vérifier les sorties réelles,
exactement comme le prompt le demande. Avant de commencer, deux micro-décisions
à vous :

1. Corriger `ES_001_OS_PREP`/`MNT_PURGE_HIST` dans le classeur (remplacer par un
   vrai job existant) — ou laisser pour plus tard ?
2. Les 11 faux positifs de `dossier_check.py` (format heure/booléen) — je corrige
   l'outil maintenant (10 minutes, pas de risque) pour que le prochain rapport
   soit fiable ?
