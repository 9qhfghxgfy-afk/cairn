# Cairn

Local-first iOS chat client for on-device and self-hosted LLMs. Original design; no
subscriptions, no paywalls, no message caps, no telemetry.

Read first: [PRD.md](PRD.md) · [ARCHITECTURE.md](ARCHITECTURE.md) ·
[ROADMAP.md](ROADMAP.md) · agent rules in [.clinerules](.clinerules)

## Status

Milestone 1: **done** — the app shell, the parent-linked chat tree, mock streaming with
real cancellation and metrics, and the SwiftData store are green end to end on CI:
[run 43685125186](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/43685125186) on
commit `1e7e250` — privacy guards, domain tests on macOS, generated-project build, and
the full simulator suite on iPhone 17 / iOS 26.5 all pass. The repository is
`github.com/9qhfghxgfy-afk/cairn`, public so the macOS CI lane stays free.
Next: Milestone 2 (remote providers over `tailscale serve` HTTPS). To install a build on
a physical iPhone: [docs/INSTALL.md](docs/INSTALL.md).

## Layout

```
project.yml                     the .xcodeproj is generated from this, never committed
App/CairnApp.swift              app entry; wires SwiftDataStore + EphemeralStore + mock engine
Packages/CairnChatDomain        Swift 6 strict, pure: tree, session, streaming, providers
Packages/CairnPersistence       SwiftData records + store (the only SwiftData module)
Packages/CairnAppUI             SwiftUI views + Cairn identity
Tests/CairnTests                simulator tests: SwiftData persistence, workspace wiring
Entitlements/                   release-clean reference + paid-path memory-limit experiment
docs/INSTALL.md                 sideloading a CI IPA onto a physical iPhone (Windows)
Scripts/ci.sh                   the exact sequence CI runs
Scripts/check-logging.sh        fails on prompt/response/secret logging
Scripts/check-ats.sh            fails on ANY ATS exception in any configuration
Scripts/check-hostname.sh       fails if a real *.ts.net hostname is tracked
.github/workflows/ci.yml        macos-26 + Xcode 26.6, iPhone 17 / iOS 26.5
.github/workflows/ipa.yml       workflow_dispatch: unsigned device IPA for sideloading
```

## Build

The authoring machine is Windows with no Xcode, so builds happen on CI, and the same
commands work on any Mac:

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project Cairn.xcodeproj -scheme Cairn \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Cairn.xcodeproj -scheme Cairn \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test
```

Or one shot: `Scripts/ci.sh all`. Fast loop for the pure domain:
`swift test --package-path Packages/CairnChatDomain`.

## Why the CI lane is shaped this way

The pinned runner (`macos-26`, Xcode 26.6) tops out at the **iOS 26.5 SDK**, so the app
targets iOS 26.0 and builds against 26.5. The `xcode-27` runner image is public preview,
so it runs a nightly forward-compatibility probe instead of gating milestones. XcodeGen
is not preinstalled on macOS runners, so CI installs it. Standard macOS runners are free
on **public** repositories, which is what keeps the project subscription-free — a private
repo bills macOS minutes at $0.062/min.
