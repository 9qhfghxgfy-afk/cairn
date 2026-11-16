#!/usr/bin/env bash
# Privacy guard: prompt text, response text, attachments, and secrets must never be
# logged. Console logging is the easiest way to leak them by accident, so it fails CI
# instead of relying on discipline.
#
# Log typed metadata only: UUIDs, enums, counts, byte sizes, durations.
set -euo pipefail

cd "$(dirname "$0")/.."

FAIL=0
SCAN=(Packages App)
EXCLUDE_TESTS="Tests/"

matches() {
  # $1 = pattern
  # Build output is excluded, and only build output. `.build/` and `DerivedData/` hold compiler
  # products plus SwiftPM's own generated test runner, which legitimately contains fatalError();
  # scanning them made this guard fail on any machine that had ever run `swift test`, which is
  # every Mac in the primary loop. The guard polices hand-written sources. CI is unaffected: it
  # checks out a clean tree where those directories do not exist, so every tracked source is
  # still scanned there. check-hostname.sh and check-signing.sh are immune to the same problem
  # because they enumerate `git ls-files` rather than the working tree.
  #
  # Only file:line is printed, never the matched line. The matched line is the one place a prompt
  # body, a response body, or a token-bearing URL could actually be echoed, and a CI log on a public
  # repo is a published artifact. The developer gets the position; the value stays out of the log.
  grep -rnE --include='*.swift' \
    --exclude-dir=.build --exclude-dir=.swiftpm --exclude-dir=DerivedData --exclude-dir=build \
    "$1" "${SCAN[@]}" 2>/dev/null \
    | grep -v "/Tests/" \
    | cut -d: -f1,2 || true
}

check() {
  local name="$1" pattern="$2" hits
  hits="$(matches "$pattern")"
  if [[ -n "$hits" ]]; then
    echo "FAIL: ${name}"
    echo "$hits"
    FAIL=1
  else
    echo "ok: ${name}"
  fi
}

check "no print()" '\bprint\('
check "no NSLog()" '\bNSLog\('
check "no debugPrint()" '\bdebugPrint\('
check "no os_log writes" '\bos_log[a-zA-Z_]*\('
check "no fatalError in library code" '\bfatalError\('

if [[ "$FAIL" -ne 0 ]]; then
  cat <<'MSG'

Cairn logs typed metadata only. If you need diagnostics, log identifiers,
enums, counts, byte sizes, or durations — never message bodies, attachment
bytes, URLs that carry tokens, or anything from Keychain.
MSG
  exit 1
fi

echo "logging guard passed"
