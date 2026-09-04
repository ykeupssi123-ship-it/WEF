#!/bin/bash
# PKI_011 - WEF_PKI_BLD_PERMRSTRCT
# Verrouillage hermetique : interdiction de l'acces public, lecture
# stricte reservee au groupe partage factory_crypto.
# JOB PASSERELLE : ouvre vers ES et LS (PKI_CRYPTO_ARMED).
set -uo pipefail
source "$VARS_FILE"

echo "[PKI_011] Verrouillage des permissions sur ${PKI_DIR}..."
# Correctif 2026-08-14 (audit config) : chemin parent auparavant en dur
# (/etc/pki/factory) alors que PKI_DIR est la variable de reference dans
# vars.conf - si PKI_DIR est un jour repointe, cette ligne chownait le
# mauvais dossier (ou un dossier inexistant) en silence. Derive maintenant
# du meme PKI_DIR que le reste du job.
chown -R root:"${CRYPTO_GROUP}" "$(dirname "${PKI_DIR}")"
chmod 750 "${PKI_DIR}"
chmod 640 "${PKI_DIR}"/*
echo "[PKI_011] OK."
exit 0
