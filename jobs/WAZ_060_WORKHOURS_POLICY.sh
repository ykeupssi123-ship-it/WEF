#!/bin/bash
# WAZ_060_WORKHOURS_POLICY - WEF_WAZ_RUN_WORKHOURS
#
# AJOUTE LE 2026-09-29, REVU LE 2026-09-30 - repond a l'objectif
# Architecture "Differenciation des heures ouvrees (utilisateur simple /
# administrateur)" (Securite > Detection d'intrusion).
#
# REVU LE 2026-09-30 (demande explicite : deux plages horaires DISTINCTES
# par role, pas une plage unique avec severite differente) : les
# administrateurs (ADMIN_USERS) sont autorises ADMIN_WORKHOURS_START a
# ADMIN_WORKHOURS_END ; les utilisateurs standards (STANDARD_USERS) sont
# autorises USER_WORKHOURS_START a USER_WORKHOURS_END - deux politiques
# independantes, jamais une seule plage partagee.
#
# MECANISME : deux listes CDB explicites (admin-users, standard-users) -
# jamais une negation ("pas dans la liste admin"), que le format Wazuh ne
# permet pas d'exprimer proprement. Un compte absent des DEUX listes
# n'est gouverne par aucune regle ici (perimetre honnete : seuls les
# comptes explicitement declares sont surveilles).
#
# Le format Wazuh <time> ne permet pas d'exprimer directement une
# negation ("hors de X-Y") en une seule regle : deux fenetres explicites
# sont donc posees par role (00:00->debut et fin->23:59), qui couvrent
# ensemble tout ce qui est hors de la plage autorisee POUR CE ROLE.
#
# LIMITE HONNETE, non contournee : la regle de base utilisee ici
# (authentification SSH reussie) suppose l'id vendor 5715 - jamais
# confirme contre le ruleset reellement installe sur VM1 (meme reserve
# que WAZ_059 pour l'id vulners). A verifier au premier test reel : si
# l'id differe, ajuster <if_sid> dans local_rules.xml (bloc
# WEF_WORKHOURS_RULE) en consequence, sans rejouer ce job (l'ossec.conf/
# listes CDB restent valables).
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

write_cdb_list() {
  local list_file="$1" csv_value="$2" tag="$3" label="$4"
  echo "[WAZ_060_WORKHOURS_POLICY] Generation de la liste CDB ${label} (${list_file})..."
  mkdir -p "$(dirname "$list_file")"
  : > "$list_file"
  IFS=',' read -ra ENTRIES <<< "$csv_value"
  local count=0
  for entry in "${ENTRIES[@]}"; do
    entry="$(echo "$entry" | xargs)"
    [ -z "$entry" ] && continue
    echo "${entry}:${tag}" >> "$list_file"
    count=$((count+1))
  done
  chmod 640 "$list_file"
  echo "[WAZ_060_WORKHOURS_POLICY] ${count} compte(s) ${label} declare(s)."
  echo "$count"
}

ADMIN_LIST_FILE="/var/ossec/etc/lists/admin-users"
STANDARD_LIST_FILE="/var/ossec/etc/lists/standard-users"
ADMIN_COUNT="$(write_cdb_list "$ADMIN_LIST_FILE" "${ADMIN_USERS:?ERREUR : ADMIN_USERS doit etre defini dans vars.conf}" "admin" "administrateur")"
STANDARD_COUNT="$(write_cdb_list "$STANDARD_LIST_FILE" "${STANDARD_USERS:-}" "standard" "utilisateur standard")"

if [ "$ADMIN_COUNT" -eq 0 ] && [ "$STANDARD_COUNT" -eq 0 ]; then
  echo "[WAZ_060_WORKHOURS_POLICY] ERREUR : ADMIN_USERS et STANDARD_USERS sont tous les deux vides dans vars.conf - rien a surveiller." >&2
  exit 1
fi
[ "$STANDARD_COUNT" -eq 0 ] && echo "[WAZ_060_WORKHOURS_POLICY] AVERTISSEMENT : STANDARD_USERS est vide - la politique utilisateur standard sera posee mais ne matchera personne." >&2

OSSEC_CONF="/var/ossec/etc/ossec.conf"
[ -f "$OSSEC_CONF" ] || { echo "[WAZ_060_WORKHOURS_POLICY] ERREUR : ${OSSEC_CONF} introuvable." >&2; exit 1; }

if lsattr "$OSSEC_CONF" 2>/dev/null | grep -q '^....i'; then
  echo "[WAZ_060_WORKHOURS_POLICY] ${OSSEC_CONF} est immuable - deverrouillage temporaire avant reecriture."
  chattr -i "$OSSEC_CONF"
fi

MARKER="<!-- WEF_WORKHOURS_CONFIG (WAZ_060, genere automatiquement - ne pas editer a la main) -->"
if grep -qF "$MARKER" "$OSSEC_CONF"; then
  echo "[WAZ_060_WORKHOURS_POLICY] Bloc deja pose dans ossec.conf, retrait avant reecriture..."
  sed -i "\|^${MARKER//\//\\/}\$|,\|^<!-- WEF_WORKHOURS_CONFIG_END -->\$|d" "$OSSEC_CONF"
fi
echo "[WAZ_060_WORKHOURS_POLICY] Declaration des listes CDB dans ossec.conf..."
{
  echo "$MARKER"
  echo "<ossec_config>"
  echo "  <ruleset>"
  echo "    <list>etc/lists/admin-users</list>"
  echo "    <list>etc/lists/standard-users</list>"
  echo "  </ruleset>"
  echo "</ossec_config>"
  echo "<!-- WEF_WORKHOURS_CONFIG_END -->"
} >> "$OSSEC_CONF"
grep -qF "$MARKER" "$OSSEC_CONF" || { echo "[WAZ_060_WORKHOURS_POLICY] ERREUR : bloc absent apres ecriture (fichier verrouille ?)." >&2; exit 1; }

echo "[WAZ_060_WORKHOURS_POLICY] Reverrouillage de ${OSSEC_CONF}..."
chown root:wazuh "$OSSEC_CONF"
chmod 640 "$OSSEC_CONF"
chattr +i "$OSSEC_CONF"

ADMIN_START="${ADMIN_WORKHOURS_START:?ERREUR : ADMIN_WORKHOURS_START doit etre defini dans vars.conf}"
ADMIN_END="${ADMIN_WORKHOURS_END:?ERREUR : ADMIN_WORKHOURS_END doit etre defini dans vars.conf}"
USER_START="${USER_WORKHOURS_START:?ERREUR : USER_WORKHOURS_START doit etre defini dans vars.conf}"
USER_END="${USER_WORKHOURS_END:?ERREUR : USER_WORKHOURS_END doit etre defini dans vars.conf}"

RULES_FILE="/var/ossec/etc/rules/local_rules.xml"
[ -f "$RULES_FILE" ] || { echo "[WAZ_060_WORKHOURS_POLICY] ERREUR : ${RULES_FILE} introuvable." >&2; exit 1; }
MARKER_RULE="<!-- WEF_WORKHOURS_RULE (WAZ_060, genere automatiquement - ne pas editer a la main) -->"
if grep -qF "$MARKER_RULE" "$RULES_FILE"; then
  echo "[WAZ_060_WORKHOURS_POLICY] Regles heures ouvrees deja posees, retrait avant reecriture..."
  sed -i "\|^${MARKER_RULE//\//\\/}\$|,\|^<!-- WEF_WORKHOURS_RULE_END -->\$|d" "$RULES_FILE"
fi
echo "[WAZ_060_WORKHOURS_POLICY] Ajout des regles de correlation (admin ${ADMIN_START}-${ADMIN_END}, standard ${USER_START}-${USER_END})..."
{
  echo "$MARKER_RULE"
  echo "<group name=\"authentication_success,hors_heures,\">"
  echo "  <rule id=\"100210\" level=\"12\">"
  echo "    <if_sid>5715</if_sid>"
  echo "    <time>00:00-${ADMIN_START}</time>"
  echo "    <list field=\"srcuser\" lookup=\"match_key\">etc/lists/admin-users</list>"
  echo "    <description>Connexion ADMINISTRATEUR hors des heures ouvrees (nuit/matin, plage autorisee ${ADMIN_START}-${ADMIN_END})</description>"
  echo "    <group>hors_heures,admin,</group>"
  echo "  </rule>"
  echo "  <rule id=\"100211\" level=\"12\">"
  echo "    <if_sid>5715</if_sid>"
  echo "    <time>${ADMIN_END}-23:59</time>"
  echo "    <list field=\"srcuser\" lookup=\"match_key\">etc/lists/admin-users</list>"
  echo "    <description>Connexion ADMINISTRATEUR hors des heures ouvrees (soir, plage autorisee ${ADMIN_START}-${ADMIN_END})</description>"
  echo "    <group>hors_heures,admin,</group>"
  echo "  </rule>"
  echo "  <rule id=\"100212\" level=\"8\">"
  echo "    <if_sid>5715</if_sid>"
  echo "    <time>00:00-${USER_START}</time>"
  echo "    <list field=\"srcuser\" lookup=\"match_key\">etc/lists/standard-users</list>"
  echo "    <description>Connexion UTILISATEUR STANDARD hors des heures ouvrees (nuit/matin, plage autorisee ${USER_START}-${USER_END})</description>"
  echo "    <group>hors_heures,utilisateur,</group>"
  echo "  </rule>"
  echo "  <rule id=\"100213\" level=\"8\">"
  echo "    <if_sid>5715</if_sid>"
  echo "    <time>${USER_END}-23:59</time>"
  echo "    <list field=\"srcuser\" lookup=\"match_key\">etc/lists/standard-users</list>"
  echo "    <description>Connexion UTILISATEUR STANDARD hors des heures ouvrees (soir, plage autorisee ${USER_START}-${USER_END})</description>"
  echo "    <group>hors_heures,utilisateur,</group>"
  echo "  </rule>"
  echo "</group>"
  echo "<!-- WEF_WORKHOURS_RULE_END -->"
} >> "$RULES_FILE"
grep -qF "$MARKER_RULE" "$RULES_FILE" || { echo "[WAZ_060_WORKHOURS_POLICY] ERREUR : regles absentes apres ecriture." >&2; exit 1; }

echo "[WAZ_060_WORKHOURS_POLICY] Redemarrage de wazuh-manager pour appliquer..."
systemctl restart wazuh-manager
if ! wait_for_service_active wazuh-manager 180 5; then
  echo "[WAZ_060_WORKHOURS_POLICY] ERREUR : wazuh-manager n'a pas redemarre." >&2
  journalctl -u wazuh-manager -n 30 --no-pager 2>/dev/null || true
  exit 1
fi

echo "[WAZ_060_WORKHOURS_POLICY] OK. Administrateurs (${ADMIN_USERS}) autorises ${ADMIN_START}-${ADMIN_END} (alerte niveau 12 hors plage)."
echo "[WAZ_060_WORKHOURS_POLICY] OK. Utilisateurs standards (${STANDARD_USERS:-aucun}) autorises ${USER_START}-${USER_END} (alerte niveau 8 hors plage)."
exit 0
