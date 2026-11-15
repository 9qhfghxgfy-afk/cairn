#!/usr/bin/env bash
# ATS guard: Release / App Store configuration must ship with NO App Transport
# Security exceptions. Local-network reach is expressed with NSLocalNetworkUsage-
# Description + NSBonjourServices, which are independent of ATS.
#
# Facts this guard encodes:
#  - NSAllowsLocalNetworking covers RFC 1918, .local, and unqualified hosts, but NOT
#    Tailscale's 100.64.0.0/10.
#  - NSAllowsArbitraryLoads is ignored when NSAllowsLocalNetworking is present.
#  - NSExceptionDomains cannot match IP literals.
# So a plaintext exception, if ever needed, must name a MagicDNS hostname and must
# exist in a Debug-only plist. Release stays HTTPS-only.
set -euo pipefail

cd "$(dirname "$0")/.."

FAIL=0

# Any ATS key in the shipped Info.plist is a release-blocking exception.
if [[ -f App/Info.plist ]] && grep -q 'NSAppTransportSecurity' App/Info.plist; then
  echo "FAIL: App/Info.plist contains an NSAppTransportSecurity key."
  echo "Release builds must have zero ATS exceptions."
  FAIL=1
else
  echo "ok: no ATS key in the shipped Info.plist"
fi

# A Debug-only plist is allowed to carry exceptions, but only scoped ones.
for plist in App/Info-Debug.plist; do
  if [[ -f "$plist" ]] && grep -q 'NSAllowsArbitraryLoads' "$plist"; then
    echo "FAIL: $plist uses NSAllowsArbitraryLoads. Scope it with NSExceptionDomains."
    FAIL=1
  fi
done

if grep -rn 'NSAllowsArbitraryLoads' project.yml >/dev/null 2>&1; then
  echo "FAIL: project.yml injects NSAllowsArbitraryLoads."
  FAIL=1
else
  echo "ok: project.yml injects no arbitrary-load exception"
fi

if [[ "$FAIL" -ne 0 ]]; then
  echo "ATS guard failed"
  exit 1
fi

echo "ATS guard passed"
