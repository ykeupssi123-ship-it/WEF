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
# MECANISME : correlation par regex directe sur le champ statique
# <user> (jamais une liste CDB - voir CORRIGE LE 2026-09-30 ci-dessous).
# Un compte absent des DEUX listes n'est gouverne par aucune regle ici
# (perimetre honnete : seuls les comptes explicitement declares sont
# surveilles).
#
# Le format Wazuh <time> ne permet pas d'exprimer directement une
# negation ("hors de X-Y") en une seule regle : deux fenetres explicites
# sont donc posees par role (00:00->debut et fin->23:59), qui couvrent
# ensemble tout ce qui est hors de la plage autorisee POUR CE ROLE.
#
# CORRIGE LE 2026-09-30 (bug produit reel, trouve en testant une vraie
# tentative de connexion sur VM1 - diagnostic exhaustif via
# wazuh-bin/wazuh-logtest -v, inspection directe de ossec.log en mode
# debug) : DEUX defauts distincts de cette installation (WAZUH_VERSION
# v4.14.7, WAZUH_REVISION=rc1 - une version candidate, pas stable) ont
# ete identifies, chacun confirme par preuve directe dans les logs :
#   1. Tout fichier place dans etc/rules/ (quel que soit son nom) est
#      enumere ("Adding rule: etc/rules/X") par analysisd mais N'EST
#      JAMAIS REELEMENT LU ("Reading rules file:" n'apparait jamais
#      pour lui, alors qu'il apparait pour les 168 autres fichiers du
#      ruleset vendor) - confirme en comparant la liste complete des
#      fichiers "ajoutes" vs "lus" dans ossec.log. Corrige ici en
#      ecrivant desormais dans ruleset/rules/ (meme repertoire que le
#      ruleset vendor), avec un prefixe numerique eleve (9950-) pour
#      charger apres tous les fichiers vendor.
#   2. TOUTES les listes CDB echouent au chargement sur cette machine,
#      y compris les listes VENDOR non modifiees (ex: WARNING (7616):
#      List 'etc/lists/malicious-ioc/malicious-ip' could not be
#      loaded - une liste 100% vendor, jamais touchee par ce projet).
#      Confirme structurellement saine (fichier .cdb present, taille
#      coherente, permissions/SELinux corrects - aucun refus AVC,
#      wazuh-analysisd tourne en domaine SELinux unconfined). Racine
#      probable : defaut du build rc1 lui-meme, pas une erreur de
#      configuration de ce projet. Corrige ici en abandonnant
#      entierement le mecanisme de liste CDB au profit d'une regex
#      directe sur le champ statique <user> (dstuser, decode nativement
#      par Wazuh) - confirme fonctionnel par un test reel identique
#      (wazuh-logtest) une fois ce contournement applique.
#   3. TROUVAILLE COMPLEMENTAIRE (meme test reel) : le moteur regex par
#      DEFAUT de Wazuh (OSRegex, utilise par <user>/<field>/<match> sans
#      attribut explicite) ne supporte PAS les parentheses de
#      groupement/alternance "(a|b)" - "^(wef_user1)$" ne matchait
#      JAMAIS, meme charge sans erreur ni avertissement. Isole en
#      comparant deux regles de test identiques, l'une sans attribut,
#      l'autre avec type="pcre2" - seule la seconde matchait. Corrige en
#      ajoutant explicitement type="pcre2" a chaque <user>.
# Les trois corrections ont ete validees ENSEMBLE par un test reel
# complet (wazuh-logtest sur un evenement de connexion reel) avant
# d'etre appliquees ici.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

# Construit une alternance regex "^(a|b|c)$" a partir d'une liste CSV
# (vars.conf) - jamais une liste CDB (voir CORRIGE LE 2026-09-30 ci-dessus).
csv_to_regex_alt() {
  local csv_value="$1"
  IFS=',' read -ra ENTRIES <<< "$csv_value"
  local cleaned=()
  local entry
  for entry in "${ENTRIES[@]}"; do
    entry="$(echo "$entry" | xargs)"
    [ -z "$entry" ] && continue
    cleaned+=("$entry")
  done
  [ "${#cleaned[@]}" -eq 0 ] && { echo ""; return; }
  local IFS_SAVE="$IFS"
  IFS='|'
  echo "^(${cleaned[*]})\$"
  IFS="$IFS_SAVE"
}

ADMIN_REGEX="$(csv_to_regex_alt "${ADMIN_USERS:?ERREUR : ADMIN_USERS doit etre defini dans vars.conf}")"
[ -z "$ADMIN_REGEX" ] && { echo "[WAZ_060_WORKHOURS_POLICY] ERREUR : ADMIN_USERS est vide dans vars.conf - rien a surveiller pour les administrateurs." >&2; exit 1; }
STANDARD_REGEX="$(csv_to_regex_alt "${STANDARD_USERS:-}")"
[ -z "$STANDARD_REGEX" ] && echo "[WAZ_060_WORKHOURS_POLICY] AVERTISSEMENT : STANDARD_USERS est vide - la politique utilisateur standard sera posee mais ne matchera personne." >&2
[ -z "$STANDARD_REGEX" ] && STANDARD_REGEX='^(__wef_aucun_utilisateur_standard_declare__)$'

ADMIN_START="${ADMIN_WORKHOURS_START:?ERREUR : ADMIN_WORKHOURS_START doit etre defini dans vars.conf}"
ADMIN_END="${ADMIN_WORKHOURS_END:?ERREUR : ADMIN_WORKHOURS_END doit etre defini dans vars.conf}"
USER_START="${USER_WORKHOURS_START:?ERREUR : USER_WORKHOURS_START doit etre defini dans vars.conf}"
USER_END="${USER_WORKHOURS_END:?ERREUR : USER_WORKHOURS_END doit etre defini dans vars.conf}"

RULES_FILE="/var/ossec/ruleset/rules/9950-wef_custom_rules.xml"
if [ ! -f "$RULES_FILE" ]; then
  echo "[WAZ_060_WORKHOURS_POLICY] ${RULES_FILE} absent - creation initiale."
  : > "$RULES_FILE"
fi
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
  echo "    <user type=\"pcre2\">${ADMIN_REGEX}</user>"
  echo "    <description>Connexion ADMINISTRATEUR hors des heures ouvrees (nuit/matin, plage autorisee ${ADMIN_START}-${ADMIN_END})</description>"
  echo "    <group>hors_heures,admin,</group>"
  echo "  </rule>"
  echo "  <rule id=\"100211\" level=\"12\">"
  echo "    <if_sid>5715</if_sid>"
  echo "    <time>${ADMIN_END}-23:59</time>"
  echo "    <user type=\"pcre2\">${ADMIN_REGEX}</user>"
  echo "    <description>Connexion ADMINISTRATEUR hors des heures ouvrees (soir, plage autorisee ${ADMIN_START}-${ADMIN_END})</description>"
  echo "    <group>hors_heures,admin,</group>"
  echo "  </rule>"
  echo "  <rule id=\"100212\" level=\"8\">"
  echo "    <if_sid>5715</if_sid>"
  echo "    <time>00:00-${USER_START}</time>"
  echo "    <user type=\"pcre2\">${STANDARD_REGEX}</user>"
  echo "    <description>Connexion UTILISATEUR STANDARD hors des heures ouvrees (nuit/matin, plage autorisee ${USER_START}-${USER_END})</description>"
  echo "    <group>hors_heures,utilisateur,</group>"
  echo "  </rule>"
  echo "  <rule id=\"100213\" level=\"8\">"
  echo "    <if_sid>5715</if_sid>"
  echo "    <time>${USER_END}-23:59</time>"
  echo "    <user type=\"pcre2\">${STANDARD_REGEX}</user>"
  echo "    <description>Connexion UTILISATEUR STANDARD hors des heures ouvrees (soir, plage autorisee ${USER_START}-${USER_END})</description>"
  echo "    <group>hors_heures,utilisateur,</group>"
  echo "  </rule>"
  echo "</group>"
  echo "<!-- WEF_WORKHOURS_RULE_END -->"
} >> "$RULES_FILE"
grep -qF "$MARKER_RULE" "$RULES_FILE" || { echo "[WAZ_060_WORKHOURS_POLICY] ERREUR : regles absentes apres ecriture." >&2; exit 1; }

echo "[WAZ_060_WORKHOURS_POLICY] Reverrouillage de ${RULES_FILE}..."
chown root:wazuh "$RULES_FILE"
chmod 640 "$RULES_FILE"

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
