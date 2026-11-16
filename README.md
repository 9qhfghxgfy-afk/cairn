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
Milestone 2: **CI-verified** — remote providers over a private address: `http://` to a server on
your LAN, or that same private address carried through your router's WireGuard tunnel, with no
certificate and no hosted account. The server side is [docs/SERVERS.md](docs/SERVERS.md); getting
a build onto a physical iPhone is [docs/INSTALL.md](docs/INSTALL.md). On-device proof of the LAN
and tunnel routes is still open — see ROADMAP.

## Layout

```
project.yml                      the .xcodeproj is generated from this, never committed
App/CairnApp.swift               app entry; wires SwiftDataStore + EphemeralStore + mock engine
Packages/CairnChatDomain         Swift 6 strict, pure: tree, session, streaming, providers
Packages/CairnPersistence        SwiftData records + store (the only SwiftData module)
Packages/CairnAppUI              SwiftUI views + Cairn identity
Tests/CairnTests                 simulator tests: SwiftData persistence, workspace wiring
Entitlements/                    release-clean reference + paid-path memory-limit experiment
Config/Signing.xcconfig          bundle-id default for both targets; #includes the git-ignored Local.xcconfig
Config/Local.xcconfig.example    template for your Team ID and bundle id (copy to Local.xcconfig)
docs/BUILD-MAC.md                the main loop: build and test on a Mac, run on a real iPhone
docs/INSTALL.md                  fallback: sideload a CI-built IPA onto an iPhone from Windows
docs/SERVERS.md                  exposing your own server on the LAN, and reaching it over WireGuard
Scripts/ci.sh                    the exact sequence CI runs; on a Mac this is the local equivalent
Scripts/check-logging.sh         fails on prompt/response/secret logging
Scripts/check-ats.sh             requires the one NSAllowsLocalNetworking key; fails on any other
Scripts/check-hostname.sh        fails on a real private hostname, or a private IP that is
                                not one of the documented example addresses
Scripts/check-signing.sh         fails on a Team ID, a personal signing identity, or a pinned
                                profile in tracked files
Scripts/test-guards.sh           proves the guards still *reject* planted values, accept the
                                documented examples, and never print what they caught
.github/workflows/ci.yml        macos-26 + Xcode 26.6, iPhone 17 / iOS 26.5
.github/workflows/ipa.yml       workflow_dispatch: unsigned device IPA for sideloading
```

## Build

The development machine is an Apple Silicon Mac with Xcode, and **that is the main loop**. CI is a
second check, not the way to find out whether code compiles. The full walkthrough — signing config,
simulator, running on a real iPhone — is [docs/BUILD-MAC.md](docs/BUILD-MAC.md).

```bash
brew install xcodegen
xcodegen generate
cp Config/Local.xcconfig.example Config/Local.xcconfig   # then set your Personal Team ID in it
Scripts/ci.sh all      # guards + swift test + build + simulator test: the sequence CI runs
```

Fast loop for the pure domain: `swift test --package-path Packages/CairnChatDomain`. To build and
test on an iPhone connected to the Mac, `Scripts/ci.sh device`. `Scripts/ci.sh probe` prints local
macOS/Xcode against the CI pin when the two disagree.

The Windows route needs no Xcode at all: CI builds the guards, and a device IPA from
`ipa.yml` + Sideloadly puts a build on the phone — see [docs/INSTALL.md](docs/INSTALL.md).

## Why the CI lane is shaped this way

The pinned runner (`macos-26`, Xcode 26.6) tops out at the **iOS 26.5 SDK**, so the app
targets iOS 26.0 and builds against 26.5. The `xcode-27` runner image is public preview,
so it runs a nightly forward-compatibility probe instead of gating milestones. XcodeGen
is not preinstalled on macOS runners, so CI installs it. Standard macOS runners are free
on **public** repositories, which is what keeps the project subscription-free — a private
repo bills macOS minutes at $0.062/min.
