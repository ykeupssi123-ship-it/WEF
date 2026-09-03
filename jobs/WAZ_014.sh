#!/bin/bash
# WAZ_014 - WEF_WAZ_BLD_STARTINDXR - Demarrage du moteur de stockage
set -uo pipefail
source "$VARS_FILE"

# AJOUTE LE 2026-09-03 (incident reel deploiement MIPREL, voir
# docs/JOURNAL_TECHNIQUE.md) : wazuh-indexer 4.14.7 (JDK bundle) echoue
# systematiquement au demarrage avec "systemd: start operation timed
# out" - cause reelle trouvee dans journalctl : "java.security.
# AccessControlException: access denied (java.lang.RuntimePermission
# setContextClassLoader)" pendant l'initialisation de log4j
# (YamlConfigurationFactory), le gestionnaire de securite Java installe
# par le module Performance Analyzer n'accordant jamais cette permission
# dans son fichier de politique par defaut (verifie : le fichier livre
# par le paquet ne contient que "getClassLoader", jamais
# "setContextClassLoader" - un defaut de compatibilite du produit, pas
# une corruption de ce fichier precis - confirme par "rpm -V" : taille
# et date inchangees depuis l'installation). PAS un probleme de RAM/
# disque (verifie en reel au moment de l'incident : 6+ Gio disque libre,
# RAM disponible). Corrige ICI, avant meme la premiere tentative de
# demarrage, pour qu'un futur deploiement ne subisse jamais cette
# boucle de crash au demarrage.
POLICY_FILE="/etc/wazuh-indexer/opensearch-performance-analyzer/opensearch_security.policy"
if [ -f "$POLICY_FILE" ] && ! grep -q 'setContextClassLoader' "$POLICY_FILE"; then
  echo "[WAZ_014] Ajout de la permission JVM manquante (setContextClassLoader) a ${POLICY_FILE}..."
  cp -a "$POLICY_FILE" "${POLICY_FILE}.bak_$(date +%Y%m%d_%H%M%S)"
  sed -i '/permission java.lang.RuntimePermission "getClassLoader";/a\    permission java.lang.RuntimePermission "setContextClassLoader";' "$POLICY_FILE"
  if ! grep -q 'setContextClassLoader' "$POLICY_FILE"; then
    echo "[WAZ_014] ERREUR : l'ajout de la permission setContextClassLoader a echoue (non retrouvee apres ecriture)." >&2
    exit 1
  fi
fi

# CORRECTIF 2026-08-19 (meme famille d'incident reel que LS_026_FINAL,
# wef-elk-core) : "systemctl enable --now" ne redemarre pas un service
# deja actif. Enable + restart explicite.
echo "[WAZ_014] Demarrage de wazuh-indexer..."
systemctl daemon-reload
systemctl enable wazuh-indexer 2>/dev/null || true
if ! systemctl restart wazuh-indexer; then
  echo "[WAZ_014] ERREUR : wazuh-indexer.service n'a pas demarre. Diagnostic (journalctl -u wazuh-indexer -n 30) :"
  journalctl -u wazuh-indexer -n 30 --no-pager 2>/dev/null || true
  exit 1
fi
echo "[WAZ_014] OK."
exit 0
