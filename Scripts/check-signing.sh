#!/usr/bin/env bash
# Signing-identity guard. A Team ID and a DEVELOPMENT_TEAM assignment are personal values: they
# say whose Apple account signed a build, and a pinned profile is a per-account artefact nobody
# else can use. Those belong in the git-ignored Config/Local.xcconfig (template:
# Config/Local.xcconfig.example), never in a tracked file. This guard keeps that true.
#
# FAILS, in any tracked file, on:
#   - a DEVELOPMENT_TEAM assignment whose extracted value is not the documented placeholder
#     XXXXXXXXXX, in any form it gets written down: xcconfig `KEY = value`, pbxproj `KEY = value;`,
#     YAML `KEY: value`, or a conditional `KEY[sdk=iphoneos*] = value`;
#   - a code-signing identity that embeds a person and a team, e.g.
#     "Apple Development: someone@example.com (AB12CD34EF)";
#   - a pinned PROVISIONING_PROFILE or PROVISIONING_PROFILE_SPECIFIER with a real value.
#
# PASSES on prose that only names a setting ("set DEVELOPMENT_TEAM in Local.xcconfig"), on the
# placeholder, and on a bare CODE_SIGN_IDENTITY that carries no team.
#
# Failures print file:line only — never the matched value — so a CI log cannot carry an ID away.
set -euo pipefail

cd "$(dirname "$0")/.."

SELF='Scripts/check-signing.sh'
PLACEHOLDER='XXXXXXXXXX'
# A Team ID is 10 alphanumeric characters; an Apple ID-stamped identity carries one in parentheses.
TEAM='[A-Z0-9]{10}'

tracked() { git ls-files -z | grep -zv -x "$SELF"; }

fail=0
note() {
  if [[ $fail -eq 0 ]]; then
    fail=1
    echo "FAIL: tracked files carry a signing identity that belongs in Config/Local.xcconfig"
    echo "      (file:line only, never the value)."
  fi
  printf '  %s\n' "$1"
}

echo '--- signing-identity guard ---'

# DEVELOPMENT_TEAM: extract the assigned value and judge the value itself, so the placeholder
# passes and prose that merely names the setting cannot match at all.
while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  file="${hit%%:*}"; rest="${hit#*:}"; line="${rest%%:*}"; content="${rest#*:}"
  value="$(printf '%s' "$content" \
    | sed -nE 's/.*DEVELOPMENT_TEAM(\[[^]]*\])?[[:space:]]*[:=][[:space:]]*["'"'"']?([^"'"'"';[:space:]]+).*/\2/p' \
    | head -n 1)"
  [[ -z "$value" || "$value" == "$PLACEHOLDER" ]] && continue
  note "$file:$line DEVELOPMENT_TEAM is assigned a value that is not the placeholder"
done < <(tracked | xargs -0 grep -InE 'DEVELOPMENT_TEAM(\[[^]]*\])?[[:space:]]*[:=]' 2>/dev/null || true)

# A signing identity naming a person and a team.
identity_hits="$(tracked | xargs -0 grep -InE "(Apple Development|Apple Distribution|iPhone Developer|iPhone Distribution): [^\"]*\(${TEAM}\)" 2>/dev/null || true)"
if [[ -n "$identity_hits" ]]; then
  note 'a code-signing identity naming a person and a team'
  printf '%s\n' "$identity_hits" | cut -d: -f1,2
fi

# A pinned provisioning profile. A value that is still an unresolved $(...) build setting is fine.
profile_hits="$(tracked | xargs -0 grep -InE 'PROVISIONING_PROFILE(_SPECIFIER)?[[:space:]]*[:=][[:space:]]*["'"'"']?[^[:space:];"'"'"'$]+' 2>/dev/null |
  grep -v '\$(' || true)"
if [[ -n "$profile_hits" ]]; then
  note 'a pinned provisioning profile, which is a per-account artefact'
  printf '%s\n' "$profile_hits" | cut -d: -f1,2
fi

if [[ $fail -ne 0 ]]; then
  echo "Put personal signing values in Config/Local.xcconfig (git-ignored). The tracked template,"
  echo "Config/Local.xcconfig.example, carries only the placeholder XXXXXXXXXX."
  echo "See docs/BUILD-MAC.md for the local signing setup."
  exit 1
fi

echo 'ok: no Team ID, personal signing identity, or pinned profile in tracked files'
