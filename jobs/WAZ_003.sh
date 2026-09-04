#!/bin/bash
# WAZ_003 - WEF_WAZ_BLD_USRNEW - Utilisateurs systeme wazuh et wazuh_indexer
set -uo pipefail
source "$VARS_FILE"
echo "[WAZ_003] Creation du groupe et utilisateur ${WAZ_USER}..."
# Correctif 2026-08-14 (audit config) : nom d'utilisateur ET uid/gid (950)
# etaient en dur ici, seul cas du projet a fixer un UID explicite - tous
# les autres composants (ES_006, KB_002, LS_003, FB_006, MB_006) laissent
# useradd choisir automatiquement et ne fixent que le nom via vars.conf.
# Aligne sur ce pattern : plus de derive possible si WAZ_USER change.
getent group "${WAZ_USER}" >/dev/null || groupadd --system "${WAZ_USER}"
id "${WAZ_USER}" &>/dev/null || useradd -g "${WAZ_USER}" --system --no-create-home "${WAZ_USER}"
echo "[WAZ_003] OK."
exit 0
