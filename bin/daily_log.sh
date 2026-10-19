#!/bin/bash
# bin/daily_log.sh - the WEF daily log, written by the server. Read it with cat.
#   $APP_BIN/daily_log.sh                      today so far   (cat $STATE_DIR/daily_log/TODAY.log)
#   $APP_BIN/daily_log.sh day 2026-10-18       one day
#   $APP_BIN/daily_log.sh week|month|quarter|semester|year [key]
#   $APP_BIN/daily_log.sh period 2026-10-01 2026-10-18
#   $APP_BIN/daily_log.sh --close              cron 00:10: yesterday + every period that just ended
#   $APP_BIN/daily_log.sh --install            schedule it (every 15 min + 00:10), once
#   add --mail to send the report(s) to DAILY_LOG_MAIL_TO (vars.conf), with the SMTP settings of notify.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export APP_HOME="${APP_HOME:-$(cd "$HERE/.." && pwd)}"
[ -f "$APP_HOME/vars.conf" ] && source "$APP_HOME/vars.conf" >/dev/null 2>&1
export STATE_DIR="${STATE_DIR:-$APP_HOME/state}"

if [ "${1:-}" = "--install" ]; then
  f=/etc/cron.d/wef-daily-log
  cat > "$f" <<CRON
# WEF daily log - written by the server, read with cat
*/15 * * * * root $HERE/daily_log.sh >/dev/null 2>&1
10 0 * * *   root $HERE/daily_log.sh --close >> $STATE_DIR/daily_log/close.out 2>&1
CRON
  chmod 644 "$f"; mkdir -p "$STATE_DIR/daily_log"
  echo "installed: $f"; cat "$f"
  "$HERE/daily_log.sh" >/dev/null && echo "first report: cat $STATE_DIR/daily_log/TODAY.log"
  exit 0
fi

MAIL=no; for a in "$@"; do [ "$a" = "--mail" ] && MAIL=yes; done
[ "${1:-}" = "--close" ] && [ -n "${DAILY_LOG_MAIL_TO:-}" ] && MAIL=yes
OUT="$(python3 "$HERE/daily_log.py" "$@")"; rc=$?
echo "$OUT"
[ $rc -ne 0 ] && exit $rc
[ "$MAIL" = "yes" ] || exit 0

TO="${DAILY_LOG_MAIL_TO:-}"
if [ -z "$TO" ] || [ -z "${SMTP_HOST:-}" ] || [ -z "${SMTP_USER:-}" ] || [ ! -f "${SMTP_PASS_FILE:-/nonexistent}" ]; then
  echo "[daily_log] mail not sent: set DAILY_LOG_MAIL_TO and the SMTP settings of notify.sh in vars.conf"; exit 0
fi
tls="${SMTP_TLS_MODE:-}"; [ -z "$tls" ] && { [ "${SMTP_PORT:-587}" = "465" ] && tls=ssl || tls=starttls; }
scheme=smtp; [ "$tls" = "ssl" ] && scheme=smtps
echo "$OUT" | sed -n 's/^written: //p' | while read -r rep; do
  tmp=$(mktemp)
  { echo "From: ${NOTIF_FROM:-$SMTP_USER}"; echo "To: $TO"
    echo "Subject: [WEF] $(sed -n 2p "$rep" | cut -c1-90)"
    echo "Date: $(date -R)"; echo "Content-Type: text/plain; charset=UTF-8"; echo; cat "$rep"; } > "$tmp"
  rcpts=(); IFS=',' read -ra R <<< "$TO"; for r in "${R[@]}"; do rcpts+=(--mail-rcpt "$(echo $r | xargs)"); done
  if curl -s -S --url "$scheme://$SMTP_HOST:${SMTP_PORT:-587}" --mail-from "${NOTIF_FROM:-$SMTP_USER}" "${rcpts[@]}" \
       --user "$SMTP_USER:$(cat "$SMTP_PASS_FILE")" --upload-file "$tmp" --ssl-reqd; then
    echo "[daily_log] mailed to $TO: $rep"
  else
    echo "[daily_log] MAIL FAILED for $rep"
  fi
  rm -f "$tmp"
done
