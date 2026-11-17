#!/usr/bin/env bash
# Zero-paywall guard. Cairn has no monetization of any kind: no purchases, no subscription, no
# trial, no "Pro" tier, no upsell surface, no gated feature flag, no artificial cap on chats,
# messages, servers or models, no analytics, no telemetry. That is a product invariant
# (PRD.md), not a preference, so it is enforced in CI rather than trusted to review.
#
# FAILS, in shipped sources and build config, on:
#   - StoreKit or a purchase API (`StoreKit`, `SKPayment`, `SKProduct`, `purchase`);
#   - upsell vocabulary in code or config (`paywall`, `subscription`, `Get Pro`, `Upgrade to`,
#     `premium`, `pro tier`, `free tier`, `unlock pro`);
#   - an artificial cap identifier (`maxChat`, `chatLimit`, `maxMessage`, `maxServer`,
#     `maxProfile`, `maxModel`, `dailyQuota`, `quotaExceeded`) — a limit that exists in the code is
#     a limit the user has to live with;
#   - analytics / telemetry SDKs or hooks (`analytics`, `telemetry`, `firebase`, `mixpanel`,
#     `posthog`, `appsflyer`).
#
# SCOPE, and why it is narrow. Only what compiles into the shipped app is policed:
#   Packages/*/Sources/**/*.swift, Packages/*/Package.swift, App/**/*.swift, project.yml.
# Not scanned, on purpose:
#   - docs, ROADMAP.md, .clinerules, Scripts/ — this project's rules and documentation have to be
#     able to *name* the thing they forbid. A whole-repo grep fails on its own prose, which is
#     exactly how check-ats.sh once broke by matching a comment that merely named a banned key.
#   - test targets — a test that asserts absence necessarily contains the word.
#   - .github/workflows/*.yml — a workflow cannot put monetization into the binary, and the step
#     that runs this very guard spells the forbidden word in its own path, so scanning workflows
#     makes the guard fail on its own invocation. `project.yml` is in scope because that is where
#     an app-facing build setting or capability would actually land.
# Consequence worth knowing: no word matching a deny pattern may appear in a scanned file at all,
# not even in a comment. Rename the identifier or the comment; do not add an exception here.
#
# `maxTokens`, `max_tokens` and `num_predict` are not caps on the user — they are sampling
# parameters the user controls — so they are deliberately not matched, and the self-test proves it.
#
# Failures print file:line and the rule name only, never the matched line.
set -euo pipefail

cd "$(dirname "$0")/.."

SCOPE_RE='^(Packages/[^/]+/Sources/.*\.swift|Packages/[^/]+/Package\.swift|App/.*\.swift|project\.yml)$'

fail=0
note() {
  if [[ $fail -eq 0 ]]; then
    fail=1
    echo "FAIL: monetization, a usage cap, or a tracking hook found in shipped sources or build config."
    echo "      Cairn is free and unlimited by design (file:line only, never the matched text):"
  fi
  printf '  %s\n' "$1"
}

scan() { # <regex> -> `file:line` hits, one per line
  local re="$1" f
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    # -H forces the filename even when exactly one file matches, so the report is always file:line.
    grep -HInEi -- "$re" "$f" 2>/dev/null || true
  done < <(git ls-files | grep -E "$SCOPE_RE")
}

deny() { # <rule label> <regex>
  local hits
  # A loop rather than xargs: `xargs -r` does not exist on macOS, and command substitution drops
  # NUL bytes, so a `-z`/`-0` pipeline silently becomes one bogus filename that matches nothing.
  # A guard that scans nothing reports success, which is the one failure it must not be able to make.
  hits="$(scan "$2")"
  [[ -z "$hits" ]] && return 0
  note "$1"
  printf '%s\n' "$hits" | cut -d: -f1,2
}

echo '--- zero-monetization / zero-cap guard ---'

deny 'a purchase framework or purchase API'       '\bStoreKit\b|SKPayment|SKProduct|SK1Product|purchas'
deny 'upsell or tier vocabulary'                  'pay ?wall|subscription|get pro|upgrade to|pro upgrade|unlock pro|pro tier|free ?tier|premium'
deny 'an artificial cap on chats/messages/servers/models' 'maxChat|chatLimit|maxMessage|messageLimit|maxServer|serverLimit|maxProfile|profileLimit|maxModel|modelLimit|dailyLimit|dailyQuota|usageQuota|quotaExceeded'
deny 'a tracking or reporting hook'               'analytics|telemetry|firebase|mixpanel|posthog|appsflyer'

if [[ $fail -ne 0 ]]; then
  echo "Remove it. Cairn has no monetization, no tier, no usage cap, and no tracking hook — see"
  echo "the \"Product invariants\" section of PRD.md and docs/PARITY.md. If a rule is matching a"
  echo "legitimate word in a shipped file, rename the identifier rather than exempting it here."
  exit 1
fi

echo 'ok: no monetization, no tier, no artificial limit, no tracking hook in shipped sources'
