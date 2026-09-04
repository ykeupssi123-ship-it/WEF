#!/bin/bash
# INFRA_004_HEALTH_GUARDIAN - WEF_INFRA_RUN_HEALTHGRD - Surveillance
# permanente de la sante fonctionnelle de l'usine (point #9 de la
# mission : jobs d'exploitation continue, proposes une fois
# l'infrastructure stable).
#
# AJOUTE LE 2026-08-31. Meme mecanisme (timer systemd, jamais un demon
# classique) que INFRA_003_DEVNULL_GUARDIAN.sh - voir son en-tete pour
# le principe general. Difference de nature : INFRA_003 REPARE des
# corruptions connues et specifiques ; celui-ci ne repare rien, il
# CONSTATE et JOURNALISE (logger, donc visible par `journalctl -t
# wef-health-guardian` ou tout futur systeme d'alerte/bin/notifier.sh
# branche dessus) - jamais d'action corrective automatique sur des
# services metier (redemarrer un service en boucle sur un faux positif
# serait pire que l'absence de surveillance).
#
# CE QUI EST CONTROLE, ET POURQUOI CES POINTS PRECIS (jamais une liste
# generique) :
#   - Les 6 services reels de l'usine (WAZ_manager/indexer/dashboard,
#     ES, LS, Kibana) : deja tous vus tomber au moins une fois en
#     boucle de crash silencieuse aujourd'hui (wazuh-dashboard) - un
#     controle regulier aurait signale l'incident en 5 minutes au lieu
#     d'attendre une verification manuelle.
#   - dnsmasq + une resolution DNS reelle (pas juste "actif") : matche
#     la meme discipline que DNS_004_START (verifier la fonction, pas
#     l'etat systemd).
#   - Expiration du certificat PKI d'usine : une CA/certificat expire en
#     silence est un classique de panne differee - personne ne le
#     remarque avant que TOUT le TLS interne casse d'un coup.
#   - Espace disque sur / : cause racine reelle et deja vecue
#     aujourd'hui (incident disque plein pendant l'orchestrateur).
set -uo pipefail
source "$VARS_FILE"

CHECK_SCRIPT="/usr/local/sbin/wef-health-check.sh"
SERVICE_FILE="/etc/systemd/system/wef-health-guardian.service"
TIMER_FILE="/etc/systemd/system/wef-health-guardian.timer"
PKI_CERT="${PKI_DIR}/factory_fullchain.pem"

echo "[INFRA_004] Installation du script de controle ${CHECK_SCRIPT}..."
cat > "$CHECK_SCRIPT" << SCRIPTEOF
#!/bin/bash
# Controle de sante fonctionnelle - genere par jobs/INFRA_004_HEALTH_GUARDIAN.sh.
# Jamais verbeux en fonctionnement normal (tourne toutes les 5 min en
# permanence) - seul un ecart reel est journalise.
SERVICES="wazuh-manager wazuh-indexer wazuh-dashboard elasticsearch logstash kibana dnsmasq"
for SVC in \$SERVICES; do
  if ! systemctl is-active --quiet "\$SVC" 2>/dev/null; then
    logger -t wef-health-guardian "ALERTE : \$SVC n'est pas actif (systemctl is-active)."
  fi
done

if ! dig +short +time=3 +tries=1 "@127.0.0.1" "elk-core.${DNS_DOMAIN:-wef.local}" A >/dev/null 2>&1; then
  logger -t wef-health-guardian "ALERTE : resolution DNS locale (elk-core.${DNS_DOMAIN:-wef.local}) en echec."
fi

if [ -f "$PKI_CERT" ]; then
  ENDDATE=\$(openssl x509 -enddate -noout -in "$PKI_CERT" 2>/dev/null | cut -d= -f2)
  if [ -n "\$ENDDATE" ]; then
    ENDEPOCH=\$(date -d "\$ENDDATE" +%s 2>/dev/null || echo 0)
    NOWEPOCH=\$(date +%s)
    DAYSLEFT=\$(( (ENDEPOCH - NOWEPOCH) / 86400 ))
    if [ "\$DAYSLEFT" -lt 30 ]; then
      logger -t wef-health-guardian "ALERTE : certificat PKI d'usine expire dans \${DAYSLEFT} jour(s) (${PKI_CERT})."
    fi
  fi
fi

DISK_PCT=\$(df --output=pcent / 2>/dev/null | tail -n1 | tr -dc '0-9')
if [ -n "\$DISK_PCT" ] && [ "\$DISK_PCT" -ge 85 ]; then
  logger -t wef-health-guardian "ALERTE : disque / a \${DISK_PCT}% d'utilisation."
fi
SCRIPTEOF
chmod 755 "$CHECK_SCRIPT"

echo "[INFRA_004] Installation du service/timer systemd..."
cat > "$SERVICE_FILE" << 'UNITEOF'
[Unit]
Description=Controle de sante fonctionnelle de l'usine (INFRA_004_HEALTH_GUARDIAN)

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/wef-health-check.sh
UNITEOF

cat > "$TIMER_FILE" << 'TIMEREOF'
[Unit]
Description=Declenche le controle de sante toutes les 5 minutes

[Timer]
OnBootSec=60s
OnUnitActiveSec=300s
AccuracySec=10s

[Install]
WantedBy=timers.target
TIMEREOF

systemctl daemon-reload
systemctl enable --now wef-health-guardian.timer

if ! systemctl is-active wef-health-guardian.timer >/dev/null 2>&1; then
  echo "[INFRA_004] ERREUR : wef-health-guardian.timer n'est pas actif apres activation." >&2
  systemctl status wef-health-guardian.timer --no-pager >&2 || true
  exit 1
fi

echo "[INFRA_004] OK (wef-health-guardian.timer actif, controle toutes les 5 min - voir journalctl -t wef-health-guardian)."
exit 0
