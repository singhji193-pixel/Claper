#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/claper}"
LOG_FILE="${LOG_FILE:-/var/log/claper-smoke.log}"

urls=(
  "http://127.0.0.1:4000/"
  "https://app.nextgensummit.co/"
  "https://app.nextgensummit.co/live"
  "https://ask.coreorbit.io/e/t9rzy"
)

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
  mkdir -p "$(dirname "$LOG_FILE")"
  printf "%s %s\n" "$(timestamp)" "$*" | tee -a "$LOG_FILE"
}

check_url() {
  local url="$1"
  local code

  code="$(curl -k -L -sS -o /dev/null --max-time 20 -w "%{http_code}" "$url" || true)"

  case "$code" in
    2*|3*) return 0 ;;
    *) log "FAIL url=$url status=${code:-000}"; return 1 ;;
  esac
}

failures=0

for url in "${urls[@]}"; do
  if ! check_url "$url"; then
    failures=$((failures + 1))
  fi
done

if [ "$failures" -eq 0 ]; then
  log "OK all production Claper smoke checks passed"
  exit 0
fi

log "RECOVER failures=$failures restarting Claper db/app"
cd "$APP_DIR"
docker compose -f docker-compose.yml up -d db app
sleep 30

post_failures=0

for url in "${urls[@]}"; do
  if ! check_url "$url"; then
    post_failures=$((post_failures + 1))
  fi
done

if [ "$post_failures" -eq 0 ]; then
  log "RECOVERED all production Claper smoke checks passed after restart"
  exit 0
fi

log "UNHEALTHY post_restart_failures=$post_failures"
exit 1
