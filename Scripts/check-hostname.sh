#!/usr/bin/env bash
# Hostname and address guard: nothing that identifies the user's OWN network may enter the
# repository — not in tracked files, commit messages, tests, docs, or CI logs. Three classes:
#
#   1. A mesh-VPN DNS name of the form <device>.<network>.ts.net. The placeholder
#      `your-host.your-vpn.ts.net` is the only *.ts.net value allowed in tracked files; such a
#      name is not part of Cairn's plan, so an accidental one must not appear.
#   2. A dynamic-DNS hostname pointing at a home router's VPN endpoint — a real label in one of
#      the consumer DDNS domains listed below. Cairn dials the PRIVATE address through the tunnel
#      and never the public endpoint, so no router hostname belongs in this repo at all.
#   3. A private IP literal that is not one of the documented example addresses (added
#      2026-11-15). RFC 1918 (10/8, 172.16/12, 192.168/16), the 100.64/10 block a mesh VPN
#      allocates, link-local 169.254/16, and loopback 127/8 are all checked. This is the rule
#      that catches a real LAN address — the address of the user's own model box — pasted into
#      a doc or a test by mistake.
#
# A real hostname looks like at least one label character immediately in front of the private
# domain. Prose like "`*.ts.net`", a bare domain name, or an angle-bracket placeholder like
# <host>.<network>.ts.net do NOT match. An address written with `x` octets (`192.168.x.x`) is
# prose, not a literal, and does NOT match either.
#
# Documented placeholders are allow-listed in ALLOWED_IPS below and named in .clinerules and
# docs/SERVERS.md. Anything private outside that list fails. A line containing BOTH an
# allow-listed address and a real one still fails: allow-listed addresses are blanked out
# before the private-range test runs.
#
# On failure this prints file:line ONLY, never the matched hostname or address, so the CI log
# itself cannot leak the real value.
set -euo pipefail

cd "$(dirname "$0")/.."

SELF='Scripts/check-hostname.sh'
PLACEHOLDER='your-host\.your-vpn\.ts\.net'

# One or more hostname labels immediately in front of a private-network domain.
LABEL='[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*'
VPNNAME_RE="${LABEL}\.ts\.net"
# Consumer DDNS domains that commonly front a home router's WireGuard / OpenVPN endpoint.
DDNS_DOMAINS='asuscomm\.com|synology\.me|duckdns\.org|no-ip\.com|no-ip\.org|ddns\.net|gotdns\.org|changeip\.com|hopto\.org|servebbs\.com|webhop\.me|redirectme\.net|isp-unique\.com'
DDNS_RE="${LABEL}\.(${DDNS_DOMAINS})"

# Private IPv4 literals. Octets are bounded so a version number cannot match by accident, and
# the surrounding guards stop a match inside a longer dotted number.
O='[0-9]{1,3}'
PRIVATE_IP_RE="(^|[^0-9.])(10\.${O}\.${O}\.${O}|192\.168\.${O}\.${O}|172\.(1[6-9]|2[0-9]|3[01])\.${O}\.${O}|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.${O}\.${O}|169\.254\.${O}\.${O}|127\.${O}\.${O}\.${O})([^0-9.]|\$)"

# The documented example set — the only private addresses this repository may contain. Chosen
# to be obvious teaching values and the boundary cases the classifier tests need. Anything
# private outside this list is treated as somebody's real address.
ALLOWED_IPS='0\.0\.0\.0|127\.0\.0\.1|192\.168\.1\.0|192\.168\.1\.5|192\.168\.1\.10|192\.168\.1\.20|10\.0\.0\.5|10\.0\.0\.9|10\.1\.2\.3|10\.8\.0\.0|10\.8\.0\.1|10\.8\.0\.2|172\.16\.0\.1|100\.64\.0\.0|100\.64\.1\.2|100\.127\.255\.254'

tracked() { git ls-files -z | grep -zv -x "$SELF"; }

fail=0

# 1 and 2: real hostnames.
host_hits="$(tracked | xargs -0 grep -InE "${VPNNAME_RE}|${DDNS_RE}" 2>/dev/null \
  | grep -v "$PLACEHOLDER" || true)"
if [[ -n "$host_hits" ]]; then
  fail=1
  echo "FAIL: tracked files contain a real-looking private hostname (file:line only)."
  printf '%s\n' "$host_hits" | cut -d: -f1,2
  echo "  A router's dynamic-DNS name must not appear at all: Cairn dials the private address"
  echo "  through the tunnel, never the public endpoint."
  echo "  For a mesh-VPN name use the placeholder your-host.your-vpn.ts.net."
fi

# 3: private IP literals outside the documented example set.
while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  file="${hit%%:*}"
  rest="${hit#*:}"
  line="${rest%%:*}"
  content="${rest#*:}"
  # Blank out the allow-listed examples, then test what is left.
  if printf '%s' "$content" | sed -E "s/(${ALLOWED_IPS})/0.0.0.0/g" \
      | grep -Eq "$PRIVATE_IP_RE"; then
    if [[ $fail -eq 0 ]]; then
      fail=1
      echo "FAIL: tracked files contain a private IP literal that is not a documented example (file:line only)."
    fi
    printf '%s\n' "${file}:${line}"
  fi
done < <(tracked | xargs -0 grep -InE "$PRIVATE_IP_RE" 2>/dev/null || true)

if [[ $fail -ne 0 ]]; then
  echo "Use a documented example address instead: 192.168.1.20 for a LAN host, 192.168.1.0/24 for"
  echo "a subnet, 10.8.0.1 / 10.8.0.2 for tunnel addresses, 127.0.0.1 for loopback — the full list"
  echo "is ALLOWED_IPS in this script. Write other addresses as prose like 192.168.x.x, or as"
  echo "<your-address>. Never write the user's real LAN, tunnel, or router address here."
  exit 1
fi

echo "ok: no real private hostnames, and no private IP outside the documented example set"
