#!/bin/bash
# lib/commun.sh - fonctions partagees entre orchestrator.sh, statut_live.sh,
# forcer_job.sh, geler_job.sh, liberer_job.sh. Ajoute le 2026-08-12.
#
# Avant, job_done()/component_enabled()/pid_alive() etaient dupliquees
# dans 3 scripts differents - un bugfix dans l'une exigeait de penser a
# le refaire dans les 2 autres. Point unique desormais : un correctif
# ici se propage partout automatiquement.
#
# A sourcer APRES avoir source vars.conf (utilise STATE_DIR,
# AGENT_COMPONENTS).
set -uo pipefail

job_done(){ [ -f "${STATE_DIR}/$1.ok" ]; }
mark_done(){ date -Iseconds > "${STATE_DIR}/$1.ok"; }

# Vrai si le champ COMPONENT d'une ligne jobs_table.csv (ex: "FILEBEAT"
# ou "FILEBEAT|METRICBEAT" pour "l'un ou l'autre suffit") autorise
# l'execution sur cette machine, compte tenu de AGENT_COMPONENTS.
component_enabled(){
  local component="$1"
  [ "$component" = "ALWAYS" ] && return 0
  local IFS='|'
  local -a alts
  read -ra alts <<< "$component"
  for alt in "${alts[@]}"; do
    if [[ ",${AGENT_COMPONENTS:-}," == *",${alt},"* ]]; then
      return 0
    fi
  done
  return 1
}

# Vrai si le PID donne repond encore (kill -0, sans envoyer de signal
# reel). Utilise partout ou un marqueur .running/.held est interprete,
# pour ne jamais prendre la simple PRESENCE d'un fichier pour argent
# comptant.
pid_alive(){ kill -0 "$1" 2>/dev/null; }

# GEL MANUEL (HELD), ajoute le 2026-08-12 : distinct de EN ATTENTE
# (dependance non satisfaite). Un job peut avoir toutes ses dependances
# remplies et etre pret a s'executer, mais un operateur a explicitement
# demande qu'il ne parte pas (fenetre de gel, changement en cours
# ailleurs, decision manuelle) - equivalent du statut HELD chez
# Control-M/Autosys. Voir geler_job.sh / liberer_job.sh.
job_held(){ [ -f "${STATE_DIR}/HELD/$1.held" ]; }

# COPIE LOCALE DES CERTIFICATS PKI, ajoutee le 2026-08-14 suite a un
# incident reel en pre-demo : Elasticsearch 8.19 (systeme "entitlements",
# remplacant du SecurityManager Java) refuse de lire un fichier SSL situe
# hors de son propre dossier de config, meme avec des droits Unix
# corrects (voir ES_020.sh/ES_023.sh pour le detail complet de
# l'incident). Applique par prudence a tout composant qui consomme le
# CA/certificat/cle partages depuis PKI_DIR (Logstash, Kibana, Filebeat,
# Metricbeat) : une copie locale, refaite a chaque execution du job
# (idempotente, jamais de derive avec PKI_DIR qui reste la source de
# verite unique), retire l'hypothese "lecture externe bloquee" pour de
# bon plutot que de parier composant par composant sur quelle
# version/moteur applique ou non une restriction similaire.
# Usage : local_pki_copy <dossier_cible> <utilisateur[:groupe]>
# A utiliser depuis un job avec : PROJECT_ROOT="$(dirname "$VARS_FILE")"
# puis source "$PROJECT_ROOT/lib/commun.sh" (VARS_FILE est deja exporte
# par orchestrator.sh/forcer_job.sh vers tous les jobs qu'ils lancent).
local_pki_copy(){
  local target_dir="$1"
  local owner="$2"
  mkdir -p "$target_dir"
  cp -f "${PKI_DIR}/factory_server.key" "${PKI_DIR}/factory_fullchain.pem" "${PKI_DIR}/factory_ca.crt" "$target_dir/"
  chown "$owner" "$target_dir" "$target_dir/factory_server.key" "$target_dir/factory_fullchain.pem" "$target_dir/factory_ca.crt"
  chmod 750 "$target_dir"
  chmod 640 "$target_dir/factory_server.key"
  chmod 644 "$target_dir/factory_fullchain.pem" "$target_dir/factory_ca.crt"
}

# VERIFICATION/AUTO-GUERISON /dev/null, ajoutee le 2026-08-14 suite a un
# incident reel en pre-demo : /dev/null a ete transforme en fichier
# ordinaire en pleine execution de l'orchestrateur (cause probable :
# fenetre rare de reattachement devtmpfs pendant une mise a jour
# systemd/udev via ES_001), rendant SSH inaccessible (sshd ne pouvait
# plus l'ouvrir) sans qu'aucun job du projet n'en soit la cause directe.
# Verification peu couteuse (un seul test [ -c ]) appelee avant CHAQUE
# job par l'orchestrateur : si la corruption est detectee, reparee tout
# de suite plutot que de laisser l'incident se reproduire silencieusement
# jusqu'a ce qu'un operateur humain le remarque sur WinSCP/PuTTY.
# SAUT VOLONTAIRE DE JOBS NON BLOQUANTS (SKIP_JOBS), ajoute le 2026-08-14
# suite a un cas reel : creneau demo/test chez un client trop court pour
# attendre un job lent mais sans impact fonctionnel sur la suite (ex: la
# mise a jour OS, contrairement au demarrage d'Elasticsearch dont tout
# depend reellement). Distinct de marquer_deja_fait.sh : ici, on n'attend
# jamais que le job ait ete "fait ailleurs", on decide A L'AVANCE (dans
# vars.conf, avant meme de lancer l'orchestrateur) qu'il n'a pas besoin
# de tourner cette fois-ci. Voir vars.conf pour le format de SKIP_JOBS.
job_in_skip_list(){
  local job_id="$1"
  [ -z "${SKIP_JOBS:-}" ] && return 1
  [[ ",${SKIP_JOBS}," == *",${job_id},"* ]]
}

check_dev_null(){
  if [ ! -c /dev/null ]; then
    echo "[check_dev_null] ALERTE : /dev/null n'est plus un peripherique caractere - reparation automatique..."
    rm -f /dev/null
    mknod -m 666 /dev/null c 1 3
    chown root:root /dev/null
    command -v restorecon >/dev/null 2>&1 && restorecon /dev/null 2>/dev/null || true
    echo "[check_dev_null] /dev/null repare."
  fi
}

# VERIFICATION REELLE APRES systemctl start/restart, ajoutee le 2026-08-14
# suite a un incident reel en pre-demo (ES_052) : un job qui se contente
# du code de sortie de "systemctl start/restart" (ou pire, qui ne le lit
# meme pas) peut se declarer OK alors que le service n'a jamais reellement
# redemarre - notamment juste apres un crash-test (pkill -9) ou "systemctl
# start" peut arriver PENDANT que systemd n'a pas encore fini de constater
# la mort du processus : sur une unite encore crue "active", la commande
# ne fait rien et rend quand meme un code de sortie 0. Audit du
# 2026-08-14 : meme famille de risque trouvee dans ES_055, KB_024,
# WAZ_028, WAZ_035_MODE_CONVERGENT, WAZ_039_MODE_SOUVERAIN - point unique
# desormais, plutot que 6 copies quasi-identiques de la meme boucle de
# verification qui auraient fini par diverger.
# Usage : wait_for_service_active <unite_systemd> [max_secondes=120] [intervalle=5]
# Retourne 0 des que l'unite est confirmee "active" (systemctl is-active),
# 1 si elle ne l'est toujours pas au bout du delai (avec le statut complet
# affiche sur stderr pour diagnostic immediat - jamais un echec silencieux).
#
# CORRIGE LE 2026-08-30 (incident reel wef-elk-core, premier passage
# complet de la chaine) : un seul "active" instantane ne suffit PAS a
# distinguer un service reellement stable d'un service en BOUCLE DE
# CRASH rapide (Restart=always, RestartSec tres court, souvent 100ms par
# defaut) - confirme en reel sur wazuh-dashboard.service (compteur de
# redemarrage systemd a 21 et grimpant, echec fatal ~1s apres chaque
# demarrage sur une erreur ENOENT de certificat), que ce garde-fou a
# pourtant laisse passer comme "actif" au moins une fois (WAZ_039
# l'a rapporte OK) : le cycle crash/redemarrage de ce service dure
# environ 7s, et is-active peut repondre "active" durant la fraction de
# seconde ou le process vient d'etre relance mais n'a pas encore
# atteint son point de defaillance - une simple coïncidence de timing
# avec l'intervalle de sondage (5s par defaut), pas une preuve de
# stabilite. Corrige : apres un premier "active", une SECONDE
# confirmation est exigee apres une courte pause (moitie de
# l'intervalle, jamais moins de 3s) - un service qui s'ecroule en
# boucle rapide n'y survit jamais, un service reellement stable ne s'en
# apercoit meme pas.
wait_for_service_active(){
  local service="$1"
  local max_secondes="${2:-120}"
  local intervalle="${3:-5}"
  local tentatives=$(( max_secondes / intervalle ))
  [ "$tentatives" -lt 1 ] && tentatives=1
  local confirm_pause=$(( intervalle / 2 ))
  [ "$confirm_pause" -lt 3 ] && confirm_pause=3

  local i etat etat_confirme
  for i in $(seq 1 "$tentatives"); do
    etat="$(systemctl is-active "$service" 2>/dev/null || true)"
    case "$etat" in
      active)
        sleep "$confirm_pause"
        etat_confirme="$(systemctl is-active "$service" 2>/dev/null || true)"
        if [ "$etat_confirme" = "active" ]; then
          return 0
        fi
        echo "[wait_for_service_active] AVERTISSEMENT : ${service} etait actif puis ne l'etait deja plus ${confirm_pause}s apres (boucle de crash ?) - nouvelle tentative." >&2
        ;;
      activating|reloading)
        : # demarrage deja en cours (systemd a pris en compte un start precedent), on repatiente
        ;;
      *)
        # failed / inactive / etat inconnu : on (re)tente le demarrage
        systemctl start "$service" 2>/dev/null || true
        ;;
    esac
    sleep "$intervalle"
  done

  echo "[wait_for_service_active] ERREUR : ${service} toujours pas actif (ou pas stable) apres ${max_secondes}s. Statut :" >&2
  systemctl status "$service" --no-pager >&2 || true
  return 1
}

# LECTURE DE SECRET DEPUIS FICHIER SEPARE, ajoutee le 2026-08-30 suite a
# un audit reel de vars.conf : WAZ_INDEXER_ADMIN_PASSWORD, WAZ_API_PASSWORD,
# LDAP_BIND_PASSWORD et FACTORY_SSH_PASSWORD vivaient en clair dans
# vars.conf - livre tel quel dans l'archive de deploiement, donc un vrai
# secret (mot de passe root des serveurs de l'usine, entre autres) s'est
# retrouve dans un artefact destine a etre redepose ailleurs. Meme defaut
# deja evite pour SMTP_PASS_FILE (voir notifier.sh) - ce point unique
# generalise ce reflexe a tous les autres secrets du projet.
#
# A l'origine de la decouverte : diagnostic reel de l'echec WAZ_020_VERIFY
# du 2026-08-19 - WAZ_INDEXER_ADMIN_PASSWORD valait "admin" dans vars.conf,
# qui ne respecte meme pas la politique de mot de passe de
# wazuh-indexer (majuscule + minuscule + chiffre + symbole parmi
# .*+?- , 8-64 caracteres) - ce mot de passe n'a donc jamais pu etre
# valide, exactement le diagnostic deja documente dans l'en-tete de
# WAZ_013C_INDXR_ADMINCERT.sh.
#
# Usage : read_or_generate_secret <fichier_secret> <generer:oui|non>
# Retourne la valeur sur stdout (jamais affichee/journalisee par cette
# fonction elle-meme - c'est la responsabilite de l'appelant de ne
# jamais la faire transiter dans un echo/log). Comportement :
#   - fichier present : le lit et le retourne tel quel (jamais regenere
#     tant qu'il existe - idempotent, une valeur stable dans le temps).
#   - fichier absent, generer=non : erreur claire, code de sortie 1
#     (JAMAIS de valeur par defaut devinee). Reserve aux secrets d'un
#     systeme EXTERNE (LDAP, SSH d'un serveur tiers) qu'on ne peut pas
#     inventer a la place de l'operateur.
#   - fichier absent, generer=oui : genere une valeur aleatoire conforme
#     a la politique de mot de passe de wazuh-indexer (voir ci-dessus),
#     l'ecrit (chmod 600) puis la retourne. Reserve aux secrets d'un
#     service que cette usine possede et controle entierement de bout
#     en bout (aucune raison de faire deviner une valeur a l'operateur
#     pour son propre mot de passe interne).
read_or_generate_secret(){
  local secret_file="$1"
  local generer="${2:-non}"

  if [ ! -f "$secret_file" ]; then
    if [ "$generer" != "oui" ]; then
      echo "[read_or_generate_secret] ERREUR : ${secret_file} introuvable." >&2
      echo "[read_or_generate_secret] Creez-le : echo 'valeur' > ${secret_file} && chmod 600 ${secret_file}" >&2
      return 1
    fi
    mkdir -p "$(dirname "$secret_file")"
    # Construction deterministe (jamais laissee au hasard qu'une classe
    # de caractere manque) : 1 majuscule + 1 minuscule + 1 chiffre + 1
    # symbole AUTORISE (".") + 20 caracteres alphanumeriques aleatoires
    # (openssl rand, jamais /dev/urandom lu a la main). tr ne conserve
    # QUE l'alphanumerique : aucun risque d'introduire un symbole hors
    # de la liste autorisee (.*+?-) dans la partie aleatoire.
    local alea
    alea="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 20)"
    local valeur="Xx9.${alea}"
    printf '%s' "$valeur" > "$secret_file"
    chmod 600 "$secret_file"
    echo "[read_or_generate_secret] ${secret_file} genere automatiquement (premiere execution, secret interne a l'usine)." >&2
  fi
  cat "$secret_file"
}
