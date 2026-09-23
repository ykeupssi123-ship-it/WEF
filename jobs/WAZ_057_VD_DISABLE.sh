#!/bin/bash
# WAZ_057_VD_DISABLE - WEF_WAZ_RUN_VDDISABLE
#
# AJOUTE LE 2026-09-23 (incident reel, wef-elk-core, diagnostique en
# creusant pourquoi le Vulnerability Detector affichait 0 detection
# malgre un module "actif") : deux causes structurelles, jamais un bug
# de config, confirmees par lecture directe d'ossec.log :
#   (1) "Vulnerability scanner in manager still disabled" - le manager
#       lui-meme est TOUJOURS exclu du scan par defaut Wazuh
#       (managerDisabledScan=1, non modifiable ici).
#   (2) "OS scan for platform 'ol' on Agent '002' is not supported." -
#       le scanner de vulnerabilites de Wazuh 4.14.7 ne sait PAS faire
#       correspondre les paquets Oracle Linux ('ol') a une base CVE -
#       limite reelle du produit, confirmee dans le journal du module
#       lui-meme, pas une supposition.
# Consequence directe, verifiee : sur une infrastructure 100% Oracle
# Linux (WEF entier), ce module ne peut STRUCTURELLEMENT produire aucune
# alerte, quelle que soit la duree d'attente - tout en telechargeant en
# continu une base CVE de ~12G dans /var/ossec/queue/vd (feed-update-
# interval 60m), qui a fait chuter la marge disque de wef-elk-core a
# 7,5G (sous le seuil de securite de 10G deja documente par
# WAZ_044_VD_SAFE_RETRY.sh). Corrige manuellement en direct ce soir sur
# wef-elk-core (desactivation + purge, 12G recuperes) - CE JOB rend ce
# correctif reproductible (jamais laisse comme un bidouillage local
# perdu au prochain rebuild, ex. chez l'etudiante).
#
# ROLE=ELK_HOST uniquement : le scanner de vulnerabilites ne tourne que
# cote manager (wazuh-modulesd), jamais sur un AGENT_HOST.
#
# Piste ouverte, honnete : si un jour Wazuh supporte 'ol' pour la
# detection de vulnerabilites, ou si l'infrastructure migre vers une
# distribution supportee, ce job devient obsolete - reactivation
# manuelle explicite alors (jamais automatique).
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

if [ "$(id -u)" -ne 0 ]; then
  echo "[WAZ_057_VD_DISABLE] ERREUR : doit tourner en root." >&2
  exit 1
fi

OSSEC_CONF="/var/ossec/etc/ossec.conf"
[ -f "$OSSEC_CONF" ] || { echo "[WAZ_057_VD_DISABLE] ERREUR : ${OSSEC_CONF} introuvable." >&2; exit 1; }

CURRENT_STATE="$(sed -n '/<vulnerability-detection>/,/<\/vulnerability-detection>/ s#.*<enabled>\(yes\|no\)</enabled>.*#\1#p' "$OSSEC_CONF" | head -1)"
if [ "$CURRENT_STATE" = "no" ]; then
  echo "[WAZ_057_VD_DISABLE] Deja desactive (<vulnerability-detection><enabled>no</enabled></vulnerability-detection>) - rien a faire."
  echo "[WAZ_057_VD_DISABLE] OK (deja sain, rien fait)."
  exit 0
fi
if [ -z "$CURRENT_STATE" ]; then
  echo "[WAZ_057_VD_DISABLE] ERREUR : bloc <vulnerability-detection> introuvable dans ${OSSEC_CONF} - structure inattendue, correction manuelle requise." >&2
  exit 1
fi

echo "[WAZ_057_VD_DISABLE] Vulnerability Detector actif - desactivation (Oracle Linux non supporte par ce module, voir en-tete)..."
if lsattr "$OSSEC_CONF" 2>/dev/null | grep -q '^....i'; then
  echo "[WAZ_057_VD_DISABLE] ${OSSEC_CONF} est immuable (deja verrouille par WAZ_032) - deverrouillage temporaire avant reecriture."
  chattr -i "$OSSEC_CONF"
fi
# Restreint au bloc <vulnerability-detection> uniquement - ne touche
# JAMAIS le <enabled>yes</enabled> du bloc <indexer> juste en dessous
# (connexion OpenSearch, doit rester active).
sed -i '/<vulnerability-detection>/,/<\/vulnerability-detection>/ s/<enabled>yes<\/enabled>/<enabled>no<\/enabled>/' "$OSSEC_CONF"
chown root:wazuh "$OSSEC_CONF"
chmod 640 "$OSSEC_CONF"
chattr +i "$OSSEC_CONF"

CHECK_STATE="$(sed -n '/<vulnerability-detection>/,/<\/vulnerability-detection>/ s#.*<enabled>\(yes\|no\)</enabled>.*#\1#p' "$OSSEC_CONF" | head -1)"
if [ "$CHECK_STATE" != "no" ]; then
  echo "[WAZ_057_VD_DISABLE] ERREUR : la desactivation n'a pas ete appliquee correctement (etat lu : '${CHECK_STATE}')." >&2
  exit 1
fi

echo "[WAZ_057_VD_DISABLE] Redemarrage de wazuh-manager pour appliquer..."
OSSEC_LOG=/var/ossec/logs/ossec.log
RESTART_LINE=$(wc -l < "$OSSEC_LOG" 2>/dev/null || echo 0)
systemctl restart wazuh-manager
if ! wait_for_service_active wazuh-manager 180 5; then
  echo "[WAZ_057_VD_DISABLE] ERREUR : wazuh-manager n'a pas redemarre." >&2
  exit 1
fi

echo "[WAZ_057_VD_DISABLE] Attente de la confirmation reelle de desactivation dans le journal (jusqu'a 60s)..."
CONFIRMED=0
for i in $(seq 1 12); do
  if tail -n +$((RESTART_LINE + 1)) "$OSSEC_LOG" 2>/dev/null | grep -q "Vulnerability scanner module is disabled"; then
    CONFIRMED=1
    break
  fi
  sleep 5
done
if [ "$CONFIRMED" -ne 1 ]; then
  echo "[WAZ_057_VD_DISABLE] ERREUR : aucune confirmation de desactivation trouvee dans ${OSSEC_LOG} apres redemarrage." >&2
  exit 1
fi
echo "[WAZ_057_VD_DISABLE] Desactivation confirmee par le journal reel."

if [ -d /var/ossec/queue/vd ]; then
  AVANT=$(du -sh /var/ossec/queue/vd 2>/dev/null | cut -f1)
  echo "[WAZ_057_VD_DISABLE] Purge de la base CVE deja telechargee (/var/ossec/queue/vd, ${AVANT})..."
  rm -rf /var/ossec/queue/vd/*
fi

echo "[WAZ_057_VD_DISABLE] OK. Vulnerability Detector desactive et purge (Oracle Linux non supporte par ce module - voir en-tete pour le detail)."
exit 0
