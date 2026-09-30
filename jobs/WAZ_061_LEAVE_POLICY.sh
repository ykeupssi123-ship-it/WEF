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
# CORRIGE LE 2026-09-30 (bug reel trouve en testant une vraie tentative
# de connexion echouee sur VM2, confirme via wazuh-bin/wazuh-logtest) :
# chaine desormais sur 5760, pas 5716. Verifie que 5716 EXISTE et que
# 5760 en est un vrai enfant (<if_sid>5700,5716</if_sid>), MAIS Wazuh ne
# retient que le PREMIER enfant qui matche pour un parent donne - 5760
# (vendor, aucune condition supplementaire au-dela du message) gagne
# toujours avant qu'un enfant plus specifique de 5716 (comme l'etait
# cette regle) ait sa chance. Meme lecon deja tiree pour WAZ_051 (IOC) -
# chainer sur la regle QUI SE DECLENCHE REELLEMENT, jamais sur un
# ancetre plus generique, meme documente comme "le bon id".
#
# CORRIGE LE 2026-09-30 (bug produit reel, DEUX defauts distincts de
# cette installation - meme diagnostic exhaustif et meme correction que
# WAZ_060_WORKHOURS_POLICY.sh, voir ses commentaires pour le detail
# complet des preuves) :
#   1. etc/rules/*.xml n'est jamais reellement lu par analysisd sur
#      cette machine (WAZUH_REVISION=rc1), quel que soit son nom -
#      regles desormais ecrites dans ruleset/rules/9950-wef_custom_rules.xml
#      (meme fichier partage que WAZ_060, prefixe numerique eleve pour
#      charger apres le ruleset vendor).
#   2. Les listes CDB echouent TOUTES au chargement sur cette machine,
#      y compris les listes vendor non modifiees - liste conges-actifs
#      abandonnee au profit d'une regex directe sur le champ statique
#      <user> (dstuser), confirmee fonctionnelle par un test reel
#      (wazuh-logtest) avant d'etre appliquee ici.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

# Construit "^(a|b|c)$" a partir de LEAVE_USERS, apres exclusion des
# comptes ADMIN_USERS - jamais une liste CDB (voir CORRIGE LE 2026-09-30
# ci-dessus), correlee via le champ statique <user> dans la regle.
IFS=',' read -ra ADMIN_ENTRIES <<< "${ADMIN_USERS:-}"
IFS=',' read -ra LEAVE_ENTRIES <<< "${LEAVE_USERS:-}"
LEAVE_CLEANED=()
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
  LEAVE_CLEANED+=("$entry")
done
echo "[WAZ_061_LEAVE_POLICY] ${#LEAVE_CLEANED[@]} compte(s) en conge declare(s) (LEAVE_USERS)."
if [ "${#LEAVE_CLEANED[@]}" -eq 0 ]; then
  echo "[WAZ_061_LEAVE_POLICY] AVERTISSEMENT : LEAVE_USERS est vide - la regle de correlation sera posee mais ne matchera personne tant qu'aucun compte n'est declare en conge (via LEAVE_USERS puis rejeu de ce job, ou directement dans vars.conf avant un depart)." >&2
  LEAVE_REGEX='^(__wef_aucun_compte_en_conge__)$'
else
  IFS_SAVE="$IFS"
  IFS='|'
  LEAVE_REGEX="^(${LEAVE_CLEANED[*]})\$"
  IFS="$IFS_SAVE"
fi

RULES_FILE="/var/ossec/ruleset/rules/9950-wef_custom_rules.xml"
if [ ! -f "$RULES_FILE" ]; then
  echo "[WAZ_061_LEAVE_POLICY] ${RULES_FILE} absent - creation initiale."
  : > "$RULES_FILE"
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
  echo "    <if_sid>5760</if_sid>"
  echo "    <user>${LEAVE_REGEX}</user>"
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
