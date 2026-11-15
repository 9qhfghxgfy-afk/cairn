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
  grep -rnE --include='*.swift' "$1" "${SCAN[@]}" 2>/dev/null \
    | grep -v "/Tests/" || true
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
