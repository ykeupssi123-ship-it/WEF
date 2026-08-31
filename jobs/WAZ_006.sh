#!/bin/bash
# WAZ_006 - WEF_WAZ_BLD_FWINDXR - Ouverture du port d'ingestion indexer
#
# CORRIGE LE 2026-08-30 : utilisait ES_PORT (reserve a Elasticsearch,
# voir vars.conf) au lieu du port propre de wazuh-indexer - incident
# reel de collision de port avec Elasticsearch, voir
# WAZ_013D_INDXR_PORTS.sh pour le detail complet.
#
# CORRIGE LE 2026-08-31 (meme incident reel que WAZ_005.sh - voir son
# en-tete pour le diagnostic complet) : la zone "internal" n'est liee a
# AUCUNE interface reseau - le port 9200 n'etait joignable depuis
# l'exterieur que par coincidence (deja ouvert dans "public" par le
# post-install du paquet RPM wazuh-indexer, jamais par ce job). Corrige
# en ciblant "public", la seule zone reellement active sur l'interface
# (ens160).
set -uo pipefail
source "$VARS_FILE"
echo "[WAZ_006] Ouverture des ports ${WAZ_INDEXER_PORT} (http) et ${WAZ_INDEXER_TRANSPORT_PORT} (transport) (indexer Wazuh)..."
firewall-cmd --permanent --zone=public --add-port=${WAZ_INDEXER_PORT}/tcp
firewall-cmd --permanent --zone=public --add-port=${WAZ_INDEXER_TRANSPORT_PORT}/tcp
firewall-cmd --reload
echo "[WAZ_006] OK."
exit 0
