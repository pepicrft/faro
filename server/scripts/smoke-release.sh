#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

release_dir="$(cd "${1:-.once/out/mix_release/release}" && pwd)"
workdir="$(mktemp -d)"
pid=""
cleanup() {
  if [ -n "$pid" ]; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  rm -rf "$workdir"
}
trap cleanup EXIT

# Test relocation without starting or modifying Once's cached release directory.
cp -R "$release_dir" "$workdir/release"
port="${FARO_SMOKE_PORT:-44973}"
secret="$(openssl rand -hex 64)"
PHX_SERVER=true FARO_SECRET_KEY_BASE="$secret" \
  FARO_DATABASE_ENABLED="${FARO_SMOKE_DATABASE_ENABLED:-false}" PORT="$port" \
  RELEASE_DISTRIBUTION=none "$workdir/release/bin/faro" start > "$workdir/server.log" 2>&1 &
pid=$!

ready=false
for _ in {1..60}; do
  if ! kill -0 "$pid" 2>/dev/null; then break; fi
  if curl --fail --silent "http://127.0.0.1:$port/health/ready" > /dev/null; then
    ready=true
    break
  fi
  sleep 0.5
done
if [ "$ready" != true ]; then
  printf 'The relocated release did not become ready.\n' >&2
  tail -60 "$workdir/server.log" >&2
  exit 1
fi
curl --fail --silent --show-error "http://127.0.0.1:$port/health/live"
printf '\n'
status="$(curl --fail --silent --show-error "http://127.0.0.1:$port/api/v1/status")"
[[ "$status" == *'"agent_runtime":"not_configured"'* ]]
printf '%s\n' "$status"
