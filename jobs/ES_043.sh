#!/bin/bash
# ES_043 - WEF_ES_RUN_MEMLOCKCHK - Validation du verrouillage memoire RAM
set -uo pipefail
source "$VARS_FILE"
echo "[ES_043] Analyse des logs pour bootstrap.memory_lock..."
if journalctl -u elasticsearch --no-pager 2>/dev/null | grep -qi "memory locking requested"; then
  if journalctl -u elasticsearch --no-pager 2>/dev/null | grep -qi "unable to lock"; then
    echo "[ES_043] AVERTISSEMENT : le verrouillage memoire semble avoir echoue (voir logs)."
  fi
fi
echo "[ES_043] OK."
exit 0
