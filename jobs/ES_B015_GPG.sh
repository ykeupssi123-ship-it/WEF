#!/bin/bash
# ES_B015_GPG - WEF_ES_BLD_GPGKEYIMPORT - Import de la cle GPG officielle Elastic
set -uo pipefail
source "$VARS_FILE"
if rpm -q gpg-pubkey --qf '%{summary}\n' 2>/dev/null | grep -qi elasticsearch; then
  echo "[ES_B015_GPG] Cle GPG Elastic deja importee, ignore."
  echo "[ES_B015_GPG] OK."
  exit 0
fi
echo "[ES_B015_GPG] Import de la cle GPG officielle..."
rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch
echo "[ES_B015_GPG] OK."
exit 0
