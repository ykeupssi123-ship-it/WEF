#!/bin/bash
# WAZ_058_NOISE_REDUCTION - WEF_WAZ_RUN_NOISEREDUCTION
#
# AJOUTE LE 2026-09-24 (demande explicite : "comment filtre-t-on le
# bruit routinier de VM1/VM2/l'hote Windows ?"). Constate en reel dans
# le dashboard (captures de la soiree) : la regle 80730 ("Auditd:
# SELinux permission check", niveau 3) se declenche en continu, toutes
# les 3 a 30 secondes environ, SUR LES DEUX machines (wef-elk-core ET
# vm2-beats-wazuh-agent simultanement) - volume largement superieur a
# ce qu'attendrait un controle SCA periodique normal (generalement
# toutes les 12h, jamais toutes les secondes).
#
# HONNETETE SUR CE QUI N'EST PAS CONFIRME (ecrit sans acces direct a
# VM1 pour verifier en reel - jamais suppose corrige a l'aveugle) :
# la cause exacte de cette frequence elevee n'a pas ete diagnostiquee
# (hypothese la plus probable : cette regle capte une ligne auditd
# generique, potentiellement emise a chaque evaluation SELinux reelle
# du systeme, donc intrinsequement frequente - jamais confirme par
# lecture du contenu exact de l'alerte). CE JOB SUPPRIME LE SYMPTOME
# (le volume d'alertes stockees), PAS LA CAUSE - une vraie investigation
# (grep de alerts.json sur rule.id 80730, lecture du contenu complet
# d'une alerte) reste a faire separement si la cause elle-meme importe.
#
# TECHNIQUE UTILISEE (standard, documentee Wazuh) : jamais editer un
# fichier de regles VENDOR directement (ecrase a la prochaine mise a
# jour Wazuh, mauvaise pratique reelle). A la place, une regle LOCALE
# qui chaine sur l'ID bruyant via <if_sid> et fixe <level>0</level> -
# Wazuh continue de traiter l'evenement (rien de perdu au niveau
# decodeur/correlation), mais un niveau 0 n'est jamais stocke comme
# alerte (comportement Wazuh documente : level=0 = jamais alerte).
#
# NON VERIFIE EN CONDITIONS REELLES a l'ecriture de ce job (aucun acces
# direct a VM1 au moment ou ce job a ete prepare - l'operateur dormait).
# A CONFIRMER OBLIGATOIREMENT apres le premier rejeu reel : le volume de
# rule.id=80730 dans le dashboard doit tomber a zero (ou tres proche)
# dans les minutes suivant ce job, sans quoi la chaine if_sid n'aura pas
# eu l'effet attendu et merite un vrai diagnostic (voir plan de
# verification en bas de ce fichier).
#
# ROLE=ELK_HOST uniquement : les regles ne vivent que sur le manager
# (local_rules.xml, evaluees par analysisd) - jamais sur un agent.
# S'applique a TOUS les agents (Linux ET Windows), puisque analysisd
# evalue centralement les evenements de toute la flotte.
set -uo pipefail
source "$VARS_FILE"

if [ "$(id -u)" -ne 0 ]; then
  echo "[WAZ_058_NOISE_REDUCTION] ERREUR : doit tourner en root." >&2
  exit 1
fi

RULES_FILE="/var/ossec/etc/rules/local_rules.xml"
[ -f "$RULES_FILE" ] || { echo "[WAZ_058_NOISE_REDUCTION] ERREUR : ${RULES_FILE} introuvable (WAZ_025 doit avoir tourne)." >&2; exit 1; }

MARKER="<!-- WEF_NOISE_REDUCTION (WAZ_058, genere automatiquement - ne pas editer a la main) -->"
MARKER_END="<!-- WEF_NOISE_REDUCTION_END -->"
if grep -qF "$MARKER" "$RULES_FILE"; then
  echo "[WAZ_058_NOISE_REDUCTION] Bloc deja pose, retrait avant reecriture (evite les doublons a chaque rejeu)..."
  WAS_IMMUTABLE=0
  if lsattr "$RULES_FILE" 2>/dev/null | grep -q '^....i'; then
    chattr -i "$RULES_FILE"
    WAS_IMMUTABLE=1
  fi
  sed -i "\|^${MARKER//\//\\/}\$|,\|^${MARKER_END//\//\\/}\$|d" "$RULES_FILE"
else
  WAS_IMMUTABLE=0
  if lsattr "$RULES_FILE" 2>/dev/null | grep -q '^....i'; then
    chattr -i "$RULES_FILE"
    WAS_IMMUTABLE=1
  fi
fi

# ID choisi : 100301 (prochain libre confirme par grep avant ecriture -
# 100100/100101/100102/100200/100300 deja pris ce soir - 100300 a ete
# retire depuis, mais jamais reutilise pour rester traçable dans
# l'historique/journal).
echo "[WAZ_058_NOISE_REDUCTION] Ajout de la regle de suppression (id 100301, chainee sur 80730)..."
{
  echo "$MARKER"
  echo "<group name=\"noise_reduction,\">"
  echo "  <rule id=\"100301\" level=\"0\">"
  echo "    <if_sid>80730</if_sid>"
  echo "    <description>Bruit routinier supprime (Auditd: SELinux permission check, cause exacte de la frequence non diagnostiquee - voir en-tete WAZ_058)</description>"
  echo "    <group>noise_reduction,</group>"
  echo "  </rule>"
  echo "</group>"
  echo "$MARKER_END"
} >> "$RULES_FILE"
grep -qF "$MARKER" "$RULES_FILE" || { echo "[WAZ_058_NOISE_REDUCTION] ERREUR : bloc absent apres ecriture dans ${RULES_FILE}." >&2; exit 1; }

if [ "$WAS_IMMUTABLE" -eq 1 ]; then
  chown root:wazuh "$RULES_FILE"
  chmod 640 "$RULES_FILE"
  chattr +i "$RULES_FILE"
fi

echo "[WAZ_058_NOISE_REDUCTION] Redemarrage de wazuh-manager pour appliquer..."
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
systemctl restart wazuh-manager
if ! wait_for_service_active wazuh-manager 180 5; then
  echo "[WAZ_058_NOISE_REDUCTION] ERREUR : wazuh-manager n'a pas redemarre." >&2
  exit 1
fi

echo "[WAZ_058_NOISE_REDUCTION] OK. Regle 80730 ramenee au niveau 0 (plus jamais stockee comme alerte)."
echo "[WAZ_058_NOISE_REDUCTION] VERIFICATION OBLIGATOIRE (jamais confirme automatiquement par ce job) :"
echo "  1) Attendre 2-3 minutes, puis dans le dashboard : rule.id : 100301 -> doit montrer des occurrences (preuve que la regle intercepte bien)."
echo "  2) rule.id : 80730 sur la meme fenetre de temps -> doit rester a zero nouvelle occurrence APRES ce redemarrage (les anciennes, avant ce job, restent normalement visibles)."
echo "  3) Si 80730 continue d'apparaitre APRES ce redemarrage : la chaine if_sid n'a pas eu l'effet attendu - investiguer avec :"
echo "       grep '\"id\":\"80730\"' /var/ossec/logs/alerts/alerts.json | tail -3"
echo "     (lire le contenu complet - full_log/data - pour comprendre enfin la vraie cause de la frequence, jamais suppose ce soir)."
exit 0
