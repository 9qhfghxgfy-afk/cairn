#!/usr/bin/env bash
# Syntax-check every Swift source the app compiles, without Xcode.
#
# Why this exists: the Windows fallback machine has a Swift toolchain but no Xcode, so a brace left
# unbalanced in a SwiftUI file — or a `guard case … , let … ` that the parser rejects — only surfaces on
# CI, six minutes after the push. `swiftc -parse` is a syntax-only pass: it loads no modules, so
# `import SwiftUI` on Windows is not an error, and it catches exactly the class of mistake that a careful
# edit can leave behind.
#
# This is NOT a type check. It proves the file parses; it says nothing about whether the types line up, and
# it is no substitute for `Scripts/ci.sh build` / `test` on a Mac or for CI.
#
# Usage:  bash Scripts/parse-check.sh      (from anywhere; paths are relative to the repo root)
set -u
cd "$(dirname "$0")/.." || exit 2

if ! command -v swiftc >/dev/null 2>&1; then
  echo "parse-check: no swiftc on PATH — skipping, not passing." >&2
  exit 0
fi

sources=()
while IFS= read -r file; do sources+=("$file"); done < <(
  find App Packages/*/Sources Tests -name '*.swift' -type f 2>/dev/null
)

if [ ${#sources[@]} -eq 0 ]; then
  echo "parse-check: found no Swift sources — refusing to report success." >&2
  exit 1
fi

output=$(swiftc -parse "${sources[@]}" 2>&1)
errors=$(printf '%s\n' "$output" | grep -c 'error:' || true)

if [ "$errors" -ne 0 ]; then
  # Names and line numbers are fine to print; no source text is echoed here beyond the compiler's own line.
  printf '%s\n' "$output" | grep 'error:' | head -20
  echo "parse-check: $errors syntax error(s) in ${#sources[@]} files."
  exit 1
fi

echo "parse-check: ${#sources[@]} files parse clean."
