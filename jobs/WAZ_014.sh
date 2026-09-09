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
#
# CORRECTIF 2026-09-09 (incident reel deploiement MIPREL2) : meme classe
# de bug DEJA documentee et corrigee pour wazuh-manager dans WAZ_015.sh
# (2026-08-30) - son propre en-tete anticipait meme explicitement que
# wazuh-indexer/wazuh-manager/wazuh-dashboard demarrant tous les trois
# ensemble au boot pouvaient etre concernes, mais le correctif n'avait
# jamais ete applique ICI. Constate en reel : au redemarrage de la VM,
# le TimeoutStartSec vendor de wazuh-indexer.service (180s, confirme via
# "systemctl show wazuh-indexer -p TimeoutStartUSec") a ete atteint
# ("start operation timed out. Terminating.", journalctl) - service tue
# et marque "failed" DEFINITIVEMENT (aucun redemarrage automatique
# ensuite). Angle mort reel decouvert par ce meme incident : WAZ_014
# etait deja marque .ok d'un run precedent, donc jamais rejoue par
# l'orchestrateur apres ce redemarrage - seul INFRA_004_HEALTH_GUARDIAN
# (desormais actif des le debut de la chaine, voir plus haut ce jour) a
# detecte et journalise la panne (toutes les 5 min), sans jamais la
# corriger lui-meme (deliberement, voir son en-tete). Ce drop-in
# (300s, aligne sur WAZ_INDEXER_READY_TIMEOUT_SEC ci-dessous - meme
# ordre de grandeur deja prouve necessaire sous charge reelle) survit
# aux redemarrages de VM ET aux mises a jour du paquet (jamais editer le
# .service fourni directement) - protege desormais aussi le demarrage
# AUTOMATIQUE au boot par systemd, pas seulement celui declenche par ce
# job.
mkdir -p /etc/systemd/system/wazuh-indexer.service.d
cat > /etc/systemd/system/wazuh-indexer.service.d/override.conf << 'EOF'
[Service]
TimeoutStartSec=300
EOF
systemctl daemon-reload

echo "[WAZ_014] Demarrage de wazuh-indexer..."
systemctl enable wazuh-indexer 2>/dev/null || true
if ! systemctl restart wazuh-indexer; then
  echo "[WAZ_014] ERREUR : wazuh-indexer.service n'a pas demarre. Diagnostic (journalctl -u wazuh-indexer -n 30) :"
  journalctl -u wazuh-indexer -n 30 --no-pager 2>/dev/null || true
  exit 1
fi

# CORRIGE LE 2026-09-04 (incident reel, deploiement sur VM neuve,
# meme diagnostic que WAZ_037_CONVERGENT_TEST/docs/JOURNAL_TECHNIQUE.md :
# "wait_for_service_active confirme seulement que l'UNITE SYSTEMD est
# active, jamais que le PIPELINE/l'API a lui-meme fini son propre
# demarrage interne"). Constate en reel : WAZ_014A_INDXR_ADMINPW,
# lance 11 secondes seulement apres ce "OK", recevait HTTP 503 (port
# deja ouvert mais formation du cluster/plugin de securite pas encore
# terminee) - wazuh-passwords-tool.sh echouait pour la meme raison.
# Corrige par un sondage repete de l'API elle-meme, jamais un delai
# fixe parie a l'avance.
#
# CORRECTION DE FOND LE 2026-09-08 (incident reel, deploiement MIPREL2) :
# le diagnostic du 2026-09-04 et l'augmentation de budget du meme jour
# (120s->300s, RESOURCE_PROFILE=DEMO_LEGER, "pression memoire") etaient
# INCOMPLETS - un vCPU insuffisant a bien ete trouve et corrige
# separement (voir ES_B001B_CPU_CHECK), mais la VRAIE cause de fond,
# confirmee par le log applicatif reel (/var/log/wazuh-indexer/
# wazuh-cluster.log, jamais journalctl qui ne montre pas ce niveau de
# detail) est structurelle, pas une histoire de vitesse :
#   Failure no such index [.opendistro_security] retrieving configuration...
# Ce message se repete INDEFINIMENT (verifie sur plus de 20 minutes,
# CPU/RAM normaux) - l'index systeme de securite n'existe simplement pas
# encore, et RIEN ne le cree automatiquement. Il n'est cree que par
# securityadmin.sh (via wazuh-passwords-tool.sh), qui vit dans WAZ_014A -
# lequel ne peut jamais s'executer tant que CE job (WAZ_014) n'a pas
# reussi. Un vrai probleme d'oeuf et de poule : attendre plus longtemps
# ici n'aurait JAMAIS resolu la situation, quel que soit le budget.
#
# HTTP 503 sur ce point precis N'EST PAS UN ECHEC - c'est la preuve que
# le demon a bien demarre et que son plugin de securite est charge et
# repond reellement (contrairement a une connexion refusee/timeout, qui
# prouverait l'inverse) : il attend juste son initialisation, qui est le
# role explicite de WAZ_014A, pas de ce job. Accepter 503 ici PLUTOT que
# de le traiter comme "pas encore pret" debloque la chaine vers le vrai
# job responsable de l'initialisation, sans rien deleguer a l'aveugle :
# WAZ_014A verifie lui-meme, par un appel reel authentifie, que
# l'initialisation a reellement reussi avant de se declarer OK.
WAZ_INDEXER_PORT="${WAZ_INDEXER_PORT:-9200}"
WAZ_INDEXER_READY_TIMEOUT_SEC="${WAZ_INDEXER_READY_TIMEOUT_SEC:-300}"
WAZ_READY_ATTEMPTS=$(( (WAZ_INDEXER_READY_TIMEOUT_SEC + 4) / 5 ))
echo "[WAZ_014] Attente de la disponibilite reelle de l'API (jusqu'a ${WAZ_INDEXER_READY_TIMEOUT_SEC}s)..."
READY=0
for i in $(seq 1 "$WAZ_READY_ATTEMPTS"); do
  HTTP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "https://127.0.0.1:${WAZ_INDEXER_PORT}/" 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "503" ]; then
    READY=1
    break
  fi
  sleep 5
done
if [ "$READY" -ne 1 ]; then
  echo "[WAZ_014] ERREUR : wazuh-indexer actif au sens systemd mais aucune reponse HTTP apres ${WAZ_INDEXER_READY_TIMEOUT_SEC}s (dernier code : ${HTTP_CODE:-000}, connexion refusee ou timeout - jamais 503, qui est desormais accepte comme preuve de vie). Diagnostic :" >&2
  echo "[WAZ_014] --- Memoire au moment de l'echec ---" >&2
  free -h 2>/dev/null >&2 || true
  echo "[WAZ_014] --- journalctl -u wazuh-indexer -n 30 ---" >&2
  journalctl -u wazuh-indexer -n 30 --no-pager 2>/dev/null || true
  echo "[WAZ_014] --- Dernieres lignes du vrai log applicatif (plus informatif que journalctl) ---" >&2
  tail -n 30 /var/log/wazuh-indexer/*.log 2>/dev/null >&2 || true
  exit 1
fi

if [ "$HTTP_CODE" = "503" ]; then
  echo "[WAZ_014] OK (demon actif, HTTP 503 = plugin de securite charge mais pas encore initialise - normal, WAZ_014A s'en charge et le verifie reellement)."
else
  echo "[WAZ_014] OK (API deja pleinement disponible, HTTP ${HTTP_CODE})."
fi
exit 0
