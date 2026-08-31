# =====================================================================
#  WAZ_ELK_FACTORY - VARIABLES (KIT WINDOWS)
#  >>> SEUL FICHIER A MODIFIER POUR CHAQUE NOUVELLE MACHINE WINDOWS <<<
#  Aucune valeur en dur dans les jobs : tout vient d'ici.
#  Equivalent Windows de vars.conf (PowerShell ne peut pas lire un
#  fichier bash) - meme role, meme regle d'or.
# =====================================================================

# Identite du projet (apparait dans les rapports)
$PROJECT_NAME = "WAZ_ELK_FACTORY"

# IP de VM1 (ELK_HOST) - manager Wazuh ET cible Logstash (Filebeat/
# Metricbeat). Identique a FACTORY_HOST_IP dans le vars.conf Linux du
# projet - c'est la meme machine qui heberge les trois.
$FACTORY_HOST_IP = "192.168.50.128"
# Alias historique (Wazuh) - toujours la meme valeur que ci-dessus.
$WAZUH_MANAGER_IP = $FACTORY_HOST_IP

# Port d'entree Logstash pour Filebeat/Metricbeat (identique a
# LS_BEATS_PORT cote Linux, defaut 5044).
$LS_BEATS_PORT = 5044

# Nom donne a CETTE machine - DOIT ETRE UNIQUE par machine. Changez
# cette valeur avant chaque nouveau deploiement (une machine Windows =
# une copie de ce dossier avec son propre AGENT_NAME).
$AGENT_NAME = "agent-windows-01"

# ---------------------------------------------------------------------
# QUELS COMPOSANTS DEPLOYER SUR CETTE MACHINE : une machine Windows ne
# veut pas forcement les 3. Retirez de la liste ce que vous ne voulez
# PAS sur cet hote precis (les jobs du composant retire sont simplement
# sautes par l'orchestrateur, comme le filtrage par ROLE cote Linux).
#   WAZUH_AGENT -> agent Wazuh (evenements de securite -> manager, port 1514/1515)
#   FILEBEAT    -> logs (Journal des evenements Windows -> Logstash, port 5044)
#   METRICBEAT  -> metriques systeme (CPU/RAM/disque/reseau -> Logstash, port 5044)
# ---------------------------------------------------------------------
$EnabledComponents = @("WAZUH_AGENT", "FILEBEAT", "METRICBEAT")

# ---------------------------------------------------------------------
# PKI - certificat de la CA d'usine, necessaire a Filebeat/Metricbeat
# pour faire confiance au Logstash de VM1 (TLS). Il n'y a pas de canal
# automatique (SSH/SCP) depuis ce kit Windows vers VM1 : deposez
# vous-meme factory_ca.crt (recupere depuis VM1, dossier PKI_DIR du
# projet Linux) a l'emplacement ci-dessous AVANT de lancer
# l'orchestrateur - FBW_004/MBW_004 verifient sa presence et vous
# arretent avec un message clair sinon (meme logique que PKI_MODE=
# external cote Linux : jamais d'improvisation silencieuse).
# ---------------------------------------------------------------------
$PKI_CA_LOCAL_PATH = "C:\ProgramData\wef-pki\factory_ca.crt"

# ---------------------------------------------------------------------
# VERSIONS - alignees le 2026-08-11 sur les memes versions que le cote
# Linux (vars.conf : ES/LS/KB/FB/MB_PACKAGE_VERSION, WAZ_PACKAGE_VERSION)
# pour que les deux plateformes tournent la meme famille de versions,
# compatibles entre elles (voir README.md, section "Versions figees").
# Wazuh agent = MSI officiel. Filebeat/Metricbeat = archive ZIP
# officielle (pas de MSI pour les Beats sous Windows).
# ---------------------------------------------------------------------
$WAZUH_AGENT_VERSION = "4.14.7-1"
$WAZUH_AGENT_MSI_URL = "https://packages.wazuh.com/4.x/windows/wazuh-agent-$WAZUH_AGENT_VERSION.msi"

$FILEBEAT_VERSION = "8.19.14"
$FILEBEAT_ZIP_URL = "https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-$FILEBEAT_VERSION-windows-x86_64.zip"

$METRICBEAT_VERSION = "8.19.14"
$METRICBEAT_ZIP_URL = "https://artifacts.elastic.co/downloads/beats/metricbeat/metricbeat-$METRICBEAT_VERSION-windows-x86_64.zip"

# ---------------------------------------------------------------------
# DIMENSIONNEMENT RESSOURCES : rien a regler ici. Cote Windows, les 3
# composants (agent Wazuh, Filebeat, Metricbeat) sont des binaires
# legers (quelques dizaines de Mo de RAM chacun, pas de JVM Java) - ce
# n'est pas comme ES/Logstash/wazuh-indexer cote Linux (vars.conf,
# section DIMENSIONNEMENT RESSOURCES) qui ont besoin d'un heap JVM
# dimensionne selon la RAM disponible. Une machine Windows avec 3-4 Go
# de RAM et quelques Go de disque suffit largement pour les 3 agents.
# ---------------------------------------------------------------------

# Repertoires de travail
$INSTALL_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$STATE_DIR   = Join-Path $INSTALL_DIR "state"
$LOG_DIR     = Join-Path $INSTALL_DIR "logs"
