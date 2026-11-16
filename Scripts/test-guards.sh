#!/usr/bin/env bash
# Guard self-test: proves the privacy guards still REJECT what they exist to catch, still ACCEPT
# the documented placeholders, and never print the value they caught. A guard that stops matching
# looks like success forever — the one failure it cannot report about itself.
#
# Safe to keep in a public repo:
#  - nothing is planted in the working tree. Cases run in a throwaway copy of the tracked files, in
#    its own git repo (the guards read `git ls-files`, so a planted file counts once it is staged);
#  - no planted value is written whole here. Addresses and hostnames are assembled from fragments
#    ('192.168.50' plus '.36'), so this file cannot trip the guard it is testing.
# A negative case asserts both halves: non-zero exit, and no planted value in the output.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
TREE=''; pass=0; fails=0

# A minimal scratch repository holding the real guard scripts plus a spec that carries the one
# permitted ATS key. Small on purpose: the per-case guard runs stay fast enough to run on every
# commit, and the committed-tree cases at the end still prove the guards over the real layout.
# Note the planted file must never contain "http": a file that names http:// anywhere is exempt
# from the hostname rules by design (docs legitimately write http:// URLs), so a case that used a
# URL would be testing the exemption, not the rule.
tree() {
  local d="$WORK/t"; rm -rf "$d"; mkdir -p "$d/Scripts"
  cp "$ROOT/Scripts/check-hostname.sh" "$ROOT/Scripts/check-ats.sh" \
     "$ROOT/Scripts/check-signing.sh" "$d/Scripts/"
  cat > "$d/project.yml" <<'SPEC'
name: Cairn
targets:
  Cairn:
    info:
      properties:
        NSAppTransportSecurity:
          NSAllowsLocalNetworking: true
SPEC
  ( cd "$d" && git init -q && git -c core.safecrlf=false add -A -f 2>/dev/null )
  printf '%s' "$d"
}
stage()   { ( cd "$TREE" && git -c core.safecrlf=false add -A -f 2>/dev/null ); }
plant()   { local p="$TREE/$1"; shift; mkdir -p "$(dirname "$p")"; : > "$p"; printf '%s\n' "$@" >> "$p"; stage; }
append()  { local p="$TREE/$1"; shift; printf '%s\n' "$@" >> "$p"; stage; }
wipe()    { rm -f "$TREE/$1"; stage; }
restore() { ( cd "$ROOT" && tar -cf - "$1" ) | tar -xf - -C "$TREE"; stage; }

expect_reject() { # <script> <label> <planted-value>
  local out status
  out="$( cd "$TREE" && bash "Scripts/$1" 2>&1 )"; status=$?
  if [[ $status -eq 0 ]]; then echo "FAIL: $2 — passed what it must reject"; fails=$((fails+1)); return; fi
  if [[ -n "$3" ]] && printf '%s\n' "$out" | grep -qF -- "$3"; then
    echo "FAIL: $2 — rejected it, but printed the value"; fails=$((fails+1)); return; fi
  echo "ok:   $2"; pass=$((pass+1))
}
expect_accept() { # <script> <label> [tree]
  local where="${3:-$TREE}" out status
  out="$( cd "$where" && bash "Scripts/$1" 2>&1 )"; status=$?
  if [[ $status -ne 0 ]]; then
    echo "FAIL: $2 — rejected what it must accept"; printf '%s\n' "$out" | head -5
    fails=$((fails+1)); return; fi
  echo "ok:   $2"; pass=$((pass+1))
}

HOSTS=check-hostname.sh; ATS=check-ats.sh
# Fragments, so no line here is a full IPv4 literal and no assembled value is allow-listed.
lan='192.168.50'; lan_ip="${lan}.36"
tun='10.8.0';     tun_ip="${tun}.42"
cgn='100.64';     cgn_ip="${cgn}.7.9"
lld='169.254';    lld_ip="${lld}.11.7"
lp='127.0.0';     lp_ip="${lp}.53"
mesh='bunkhouse'; mesh_host="${mesh}hause"".ts.net"
ddns='nas';       ddns_host="${ddns}-office"".asuscomm.com"

echo '--- hostname / address guard: must reject, and must not print ---'
TREE="$(tree)"
plant notes.md "box sits at ${lan_ip} on the LAN";        expect_reject "$HOSTS" 'a LAN address' "$lan_ip"
plant notes.md "phone joins at ${tun_ip} in tunnel";     expect_reject "$HOSTS" 'a tunnel address' "$tun_ip"
plant notes.md "a mesh peer answers on ${cgn_ip}";       expect_reject "$HOSTS" 'a 100.64/10 address' "$cgn_ip"
plant notes.md "printer answers on ${lld_ip}";           expect_reject "$HOSTS" 'a link-local address' "$lld_ip"
plant notes.md "loopback, not an example: ${lp_ip}";     expect_reject "$HOSTS" 'loopback outside the examples' "$lp_ip"
plant notes.md "old profile host: ${mesh_host}";            expect_reject "$HOSTS" 'a mesh-VPN DNS name' "$mesh_host"
plant notes.md "router answers at ${ddns_host}:51820";   expect_reject "$HOSTS" 'a dynamic-DNS router name' "$ddns_host"
plant notes.md "192.168.1.20 is the example, ${lan_ip} real"; expect_reject "$HOSTS" 'a real address beside an example on one line' "$lan_ip"
plant App/Info.plist "plist value holding ${lan_ip}";    expect_reject "$HOSTS" 'an address in a generated plist' "$lan_ip"

echo '--- hostname / address guard: must accept ---'
wipe notes.md; wipe App/Info.plist

plant notes.md 'examples 192.168.1.20 and 192.168.1.0/24, tunnel 10.8.0.1 and 10.8.0.2, loopback 127.0.0.1, bind 0.0.0.0, boundary 100.64.1.2 and 172.16.0.1'
expect_accept "$HOSTS" 'every documented example address'
plant notes.md 'prose keeps the shape: 192.168.x.x, 10.x, 100.64/10, and 198.51.100.7 is documentation'
expect_accept "$HOSTS" 'prose forms and RFC 5737 documentation addresses'
plant notes.md 'the only allowed mesh name is your-host.your-vpn.ts.net; router name stays <your-router-hostname>'
expect_accept "$HOSTS" 'the sanctioned placeholders'
wipe notes.md; wipe App/Info.plist
expect_accept "$HOSTS" 'the unplanted copy still passes'

echo '--- ATS guard: must reject ---'
# A plist with the permitted key *and* a banned key: only the banned key can cause the failure, so
# the case cannot pass by accident.
okplist='<dict><key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/>'
TREE="$(tree)"; wipe App/Info.plist
append project.yml '        NSAllowsArbitraryLoads: true'; expect_reject "$ATS" 'NSAllowsArbitraryLoads in project.yml' ''
restore project.yml
append project.yml '        NSExceptionDomains:';          expect_reject "$ATS" 'NSExceptionDomains in project.yml' ''
restore project.yml
plant App/Info.plist "$okplist" '<key>NSAllowsArbitraryLoads</key><true/></dict></dict>'
expect_reject "$ATS" 'NSAllowsArbitraryLoads in the shipped plist' ''
plant App/Info.plist "$okplist" '<key>NSAllowsArbitraryLoadsInWebContent</key><true/></dict></dict>'
expect_reject "$ATS" 'NSAllowsArbitraryLoadsInWebContent in the shipped plist' ''
plant App/Info.plist "$okplist" '<key>NSExceptionDomains</key><dict/></dict></dict>'
expect_reject "$ATS" 'NSExceptionDomains in the shipped plist' ''
plant App/Info.plist '<dict><key>CFBundleName</key><string>Cairn</string></dict>'
expect_reject "$ATS" 'a shipped plist without NSAllowsLocalNetworking' ''

echo '--- ATS guard: must accept ---'
plant App/Info.plist "$okplist" '</dict></dict>'
expect_accept "$ATS" 'a shipped plist with only the one permitted key'
wipe App/Info.plist
expect_accept "$ATS" 'the spec-only checkout, which is what the CI guards job sees'
expect_accept "$HOSTS" 'the committed tree' "$ROOT"
expect_accept "$ATS" 'the committed tree' "$ROOT"

SIGN=check-signing.sh
# Setting names are assembled so no line of this file is a real-looking assignment, and the Team
# ID is assembled so no line here has the 10-character shape of one. Otherwise the guards would
# fail when they scan the committed tree, which this file also asserts must pass.
dtkey='DEVELOPMENT''_TEAM'; idkey='CODE_SIGN''_IDENTITY'; ppkey='PROVISIONING''_PROFILE_SPECIFIER'
team='ABCD12'"34EF"; ident='Apple Development: someone@example.com ('"ABCD12""34EF"')'
profile='home-lan-profile'

echo '--- signing-identity guard: must reject, and must not print ---'
TREE="$(tree)"
plant project.yml "          ${dtkey}: ${team}"      ; expect_reject "$SIGN" 'a Team ID in project.yml' "$team"
plant Config/Signing.xcconfig "${dtkey} = ${team}"   ; expect_reject "$SIGN" 'a Team ID in an xcconfig' "$team"
plant notes.md "${dtkey}[sdk=iphoneos*] = ${team}"   ; expect_reject "$SIGN" 'a Team ID in a conditional setting' "$team"
plant notes.md "${idkey} = \"${ident}\""             ; expect_reject "$SIGN" 'a signing identity naming a person and a team' "$team"
plant project.yml "          ${ppkey}: ${profile}"   ; expect_reject "$SIGN" 'a pinned provisioning profile' "$profile"

echo '--- signing-identity guard: must accept ---'
# Fresh tree: the reject block above plants a Team ID into project.yml and Config/Signing.xcconfig,
# and leftovers from it would fail these cases for the wrong reason.
TREE="$(tree)"
plant notes.md "set ${dtkey} in Config/Local.xcconfig, never in a tracked file"
expect_accept "$SIGN" 'prose that names the setting without assigning it'
plant Config/Local.xcconfig.example "${dtkey} = XXXXXXXXXX"
expect_accept "$SIGN" 'the tracked template carrying only the placeholder'
plant Config/Signing.xcconfig "${idkey} = iPhone Developer"
expect_accept "$SIGN" 'a bare signing identity with no team in it'
wipe notes.md; wipe Config/Signing.xcconfig; wipe Config/Local.xcconfig.example
expect_accept "$SIGN" 'the unplanted copy still passes'
expect_accept "$SIGN" 'the committed tree' "$ROOT"

echo "guard self-test: ${pass} ok, ${fails} failed"
[[ $fails -eq 0 ]] || exit 1
