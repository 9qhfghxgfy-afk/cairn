#!/usr/bin/env bash
# Hostname guard: the user's REAL MagicDNS hostname must never enter the repository —
# not in tracked files, commit messages, tests, docs, or CI logs. The placeholder
# `your-host.your-tailnet.ts.net` is the only *.ts.net value allowed in tracked files.
#
# A real MagicDNS hostname looks like <device>.<tailnet-label>.ts.net: at least one
# label character immediately before `.ts.net`. Prose like "`*.ts.net`", bare "ts.net",
# or angle-bracket placeholders like <host>.<tailnet>.ts.net do NOT match.
# Known edge: a line containing BOTH the placeholder and a real hostname would pass —
# never write a line like that.
#
# On failure this prints file:line ONLY, never the matched hostname, so the CI log
# itself cannot leak the real tailnet name.
set -euo pipefail

cd "$(dirname "$0")/.."

SELF='Scripts/check-hostname.sh'
PLACEHOLDER='your-host\.your-tailnet\.ts\.net'
HOST_RE='[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*\.ts\.net'

HITS="$(git ls-files -z | grep -zv -x "$SELF" \
  | xargs -0 grep -InE "$HOST_RE" 2>/dev/null \
  | grep -v "$PLACEHOLDER" || true)"

if [[ -n "$HITS" ]]; then
  echo "FAIL: tracked files contain a real-looking MagicDNS hostname (file:line only)."
  printf '%s\n' "$HITS" | cut -d: -f1,2
  echo "Only the placeholder your-host.your-tailnet.ts.net is permitted in tracked files."
  exit 1
fi
echo "ok: no real MagicDNS hostnames in tracked files"