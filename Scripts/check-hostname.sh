#!/usr/bin/env bash
# Hostname guard: a real hostname belonging to the user's own network must never enter the
# repository — not in tracked files, commit messages, tests, docs, or CI logs. Two kinds matter:
#   1. A mesh-VPN DNS name of the form <device>.<network>.ts.net. The placeholder
#      `your-host.your-vpn.ts.net` is the only *.ts.net value allowed in tracked files; such a
#      name is not part of Cairn's plan, so an accidental one must not appear.
#   2. A dynamic-DNS hostname pointing at a home router's VPN endpoint — a real label in one of
#      the consumer DDNS domains listed below. Cairn dials the PRIVATE address through the tunnel
#      and never the public endpoint, so no router hostname belongs in this repo at all.
#
# A real hostname looks like at least one label character immediately in front of the private
# domain. Prose like "`*.ts.net`", a bare "asuscomm.com", or an angle-bracket placeholder like
# <host>.<network>.ts.net do NOT match.
# Known edge: a line containing BOTH the placeholder and a real hostname would pass —
# never write a line like that.
#
# On failure this prints file:line ONLY, never the matched hostname, so the CI log
# itself cannot leak the real value.
set -euo pipefail

cd "$(dirname "$0")/.."

SELF='Scripts/check-hostname.sh'
PLACEHOLDER='your-host\.your-vpn\.ts\.net'

# One or more hostname labels immediately in front of a private-network domain.
LABEL='[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*'
MAGICDNS_RE="${LABEL}\.ts\.net"
# Consumer DDNS domains that commonly front a home router's WireGuard / OpenVPN endpoint.
DDNS_DOMAINS='asuscomm\.com|synology\.me|duckdns\.org|no-ip\.com|no-ip\.org|ddns\.net|gotdns\.org|changeip\.com|hopto\.org|servebbs\.com|webhop\.me|redirectme\.net|isp-unique\.com'
DDNS_RE="${LABEL}\.(${DDNS_DOMAINS})"

HITS="$(git ls-files -z | grep -zv -x "$SELF" \
  | xargs -0 grep -InE "${MAGICDNS_RE}|${DDNS_RE}" 2>/dev/null \
  | grep -v "$PLACEHOLDER" || true)"

if [[ -n "$HITS" ]]; then
  echo "FAIL: tracked files contain a real-looking private hostname (file:line only)."
  printf '%s\n' "$HITS" | cut -d: -f1,2
  echo "For a mesh-VPN name use the placeholder your-host.your-vpn.ts.net."
  echo "A DDNS hostname for a home VPN endpoint must not appear at all: Cairn dials the"
  echo "private address through the tunnel, never the public endpoint."
  exit 1
fi
echo "ok: no real MagicDNS or DDNS hostnames in tracked files"