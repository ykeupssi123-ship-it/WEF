#!/bin/bash
# WAZ_061_LEAVE_POLICY - WEF_WAZ_RUN_LEAVEPOLICY
#
# AJOUTE LE 2026-09-29 - repond a l'objectif Architecture "Politique de
# depart en conge (compte bloque, tentative de connexion, FIM)"
# (Securite > Detection d'intrusion, statut "A construire" jusqu'ici).
# Cote MANAGER (ELK_HOST) : declare la liste CDB des comptes actuellement
# en conge (LEAVE_USERS, vars.conf) et la regle de correlation qui
# transforme toute tentative de connexion sur l'un de ces comptes en
# alerte critique. Le verrouillage reel du compte (cote systeme) est
# une action separee, manuelle, par utilisateur : voir
# jobs/WAG_011_LEAVE_LOCK.sh (verrouiller) / jobs/WAG_012_LEAVE_UNLOCK.sh
# (deverrouiller au retour) sur AGENT_HOST - jamais confondu avec ce
# job-ci, qui ne fait que poser l'infrastructure de detection.
#
# FIM : reutilise integralement la surveillance deja active sur /home/*
# (perimetre pose par WAZ_050/WAG_009) - aucune configuration FIM
# supplementaire necessaire ici, toute modification du repertoire
# personnel d'un compte en conge declenche deja les regles FIM
# existantes (550/553/554).
#
# LIMITE HONNETE, non contournee : s'appuie sur la regle vendor 5716
# (authentification SSH echouee) - meme reserve que WAZ_060 sur l'id
# exact, jamais confirme contre le ruleset reellement installe sur VM1.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

LEAVE_LIST_FILE="/var/ossec/etc/lists/conges-actifs"
echo "[WAZ_061_LEAVE_POLICY] Generation de la liste CDB des comptes en conge (${LEAVE_LIST_FILE})..."
mkdir -p "$(dirname "$LEAVE_LIST_FILE")"
: > "$LEAVE_LIST_FILE"
IFS=',' read -ra ADMIN_ENTRIES <<< "${ADMIN_USERS:-}"
IFS=',' read -ra LEAVE_ENTRIES <<< "${LEAVE_USERS:-}"
COUNT=0
for entry in "${LEAVE_ENTRIES[@]}"; do
  entry="$(echo "$entry" | xargs)"
  [ -z "$entry" ] && continue
  IS_ADMIN=0
  for admin_entry in "${ADMIN_ENTRIES[@]}"; do
    [ "$(echo "$admin_entry" | xargs)" = "$entry" ] && IS_ADMIN=1
  done
  if [ "$IS_ADMIN" -eq 1 ]; then
    echo "[WAZ_061_LEAVE_POLICY] REFUS : '${entry}' figure aussi dans ADMIN_USERS - un administrateur n'est jamais soumis a la politique de conge, jamais ajoute a la liste." >&2
    continue
  fi
  echo "${entry}:conge" >> "$LEAVE_LIST_FILE"
  COUNT=$((COUNT+1))
done
chmod 640 "$LEAVE_LIST_FILE"
echo "[WAZ_061_LEAVE_POLICY] ${COUNT} compte(s) en conge declare(s) (LEAVE_USERS)."
if [ "$COUNT" -eq 0 ]; then
  echo "[WAZ_061_LEAVE_POLICY] AVERTISSEMENT : LEAVE_USERS est vide - la regle de correlation sera posee mais ne matchera personne tant qu'aucun compte n'est declare en conge (via LEAVE_USERS puis rejeu de ce job, ou directement dans vars.conf avant un depart)." >&2
fi

OSSEC_CONF="/var/ossec/etc/ossec.conf"
[ -f "$OSSEC_CONF" ] || { echo "[WAZ_061_LEAVE_POLICY] ERREUR : ${OSSEC_CONF} introuvable." >&2; exit 1; }

if lsattr "$OSSEC_CONF" 2>/dev/null | grep -q '^....i'; then
  echo "[WAZ_061_LEAVE_POLICY] ${OSSEC_CONF} est immuable - deverrouillage temporaire avant reecriture."
  chattr -i "$OSSEC_CONF"
fi

MARKER="<!-- WEF_LEAVE_CONFIG (WAZ_061, genere automatiquement - ne pas editer a la main) -->"
if grep -qF "$MARKER" "$OSSEC_CONF"; then
  echo "[WAZ_061_LEAVE_POLICY] Bloc deja pose dans ossec.conf, retrait avant reecriture..."
  sed -i "\|^${MARKER//\//\\/}\$|,\|^<!-- WEF_LEAVE_CONFIG_END -->\$|d" "$OSSEC_CONF"
fi
echo "[WAZ_061_LEAVE_POLICY] Declaration de la liste CDB dans ossec.conf..."
{
  echo "$MARKER"
  echo "<ossec_config>"
  echo "  <ruleset>"
  echo "    <list>etc/lists/conges-actifs</list>"
  echo "  </ruleset>"
  echo "</ossec_config>"
  echo "<!-- WEF_LEAVE_CONFIG_END -->"
} >> "$OSSEC_CONF"
grep -qF "$MARKER" "$OSSEC_CONF" || { echo "[WAZ_061_LEAVE_POLICY] ERREUR : bloc absent apres ecriture (fichier verrouille ?)." >&2; exit 1; }

echo "[WAZ_061_LEAVE_POLICY] Reverrouillage de ${OSSEC_CONF}..."
chown root:wazuh "$OSSEC_CONF"
chmod 640 "$OSSEC_CONF"
chattr +i "$OSSEC_CONF"

RULES_FILE="/var/ossec/etc/rules/local_rules.xml"
[ -f "$RULES_FILE" ] || { echo "[WAZ_061_LEAVE_POLICY] ERREUR : ${RULES_FILE} introuvable." >&2; exit 1; }
# CORRIGE LE 2026-09-30 (meme bug reel trouve sur WAZ_060 au premier
# test sur VM1) : local_rules.xml est verrouille immuable, jamais
# deverrouille avant cette correction.
if lsattr "$RULES_FILE" 2>/dev/null | grep -q '^....i'; then
  echo "[WAZ_061_LEAVE_POLICY] ${RULES_FILE} est immuable - deverrouillage temporaire avant reecriture."
  chattr -i "$RULES_FILE"
fi
MARKER_RULE="<!-- WEF_LEAVE_RULE (WAZ_061, genere automatiquement - ne pas editer a la main) -->"
if grep -qF "$MARKER_RULE" "$RULES_FILE"; then
  echo "[WAZ_061_LEAVE_POLICY] Regle conge deja posee, retrait avant reecriture..."
  sed -i "\|^${MARKER_RULE//\//\\/}\$|,\|^<!-- WEF_LEAVE_RULE_END -->\$|d" "$RULES_FILE"
fi
echo "[WAZ_061_LEAVE_POLICY] Ajout de la regle de correlation conge (id 100220)..."
{
  echo "$MARKER_RULE"
  echo "<group name=\"authentication_failed,conge,\">"
  echo "  <rule id=\"100220\" level=\"13\">"
  echo "    <if_sid>5716</if_sid>"
  echo "    <list field=\"srcuser\" lookup=\"match_key\">etc/lists/conges-actifs</list>"
  echo "    <description>Tentative de connexion sur un compte EN CONGE - intrusion probable</description>"
  echo "    <group>conge_intrusion,</group>"
  echo "  </rule>"
  echo "</group>"
  echo "<!-- WEF_LEAVE_RULE_END -->"
} >> "$RULES_FILE"
grep -qF "$MARKER_RULE" "$RULES_FILE" || { echo "[WAZ_061_LEAVE_POLICY] ERREUR : regle absente apres ecriture." >&2; exit 1; }

echo "[WAZ_061_LEAVE_POLICY] Reverrouillage de ${RULES_FILE}..."
chown root:wazuh "$RULES_FILE"
chmod 640 "$RULES_FILE"
chattr +i "$RULES_FILE"

echo "[WAZ_061_LEAVE_POLICY] Redemarrage de wazuh-manager pour appliquer..."
systemctl restart wazuh-manager
if ! wait_for_service_active wazuh-manager 180 5; then
  echo "[WAZ_061_LEAVE_POLICY] ERREUR : wazuh-manager n'a pas redemarre." >&2
  journalctl -u wazuh-manager -n 30 --no-pager 2>/dev/null || true
  exit 1
fi

echo "[WAZ_061_LEAVE_POLICY] OK. Toute tentative de connexion sur un compte liste dans LEAVE_USERS declenche desormais une alerte critique (niveau 13)."
echo "[WAZ_061_LEAVE_POLICY] Rappel : verrouiller reellement le compte cote systeme reste une action separee - voir WAG_011_LEAVE_LOCK.sh sur AGENT_HOST."
exit 0
