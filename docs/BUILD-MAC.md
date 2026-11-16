# Building Cairn on a Mac — this is the main loop

Decision 2026-11-15: the development machine is now an Apple Silicon MacBook Pro, so **local
Xcode is the primary build loop and GitHub CI is the second check**. Nothing about the CI lane
changed: it still runs the same sequence on every push, and a milestone is still only claimed with
a green CI run number. What changed is where you find out that something is broken — in seconds,
on your own machine, instead of after a runner picks the job up.

Everything below is commands you can paste. The one-shot version is `Scripts/ci.sh all`, which runs
exactly the sequence CI runs.

## 0. Check what you already have

```bash
sw_vers                      # macOS version
xcodebuild -version          # which Xcode, if any
xcrun simctl list runtimes   # which iOS simulator runtimes are installed
```

Xcode's minimum macOS moves with every release, and an installer that is too old for your macOS —
or a macOS too old for your installer — fails in a way that is easy to misread as a broken download.
So do not trust a number you read in a document, including this one: check the **Requirements** line
on Apple's Xcode page (or the App Store listing for Xcode) against `sw_vers` before you download.

The rule that actually matters for this repository is the other direction: CI is pinned to
**Xcode 26.6 on the `macos-26` runner**, whose SDK ceiling is iOS 26.5, and the app targets iOS 26.0.
Any Xcode from 26.6 upward builds this project. If your local Xcode is *newer* than CI's pin, a
local pass does not guarantee a CI pass — new SDKs surface new warnings and new availability. That
is precisely why CI stays the second check rather than disappearing.

## 1. Install Xcode

Get Xcode from the Mac App Store, or as a direct `.xip` from developer.apple.com (you need an Apple
ID either way; a **free** account is enough for everything in this project). Then:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
xcodebuild -version
xcodebuild -showsdks | grep -i -E 'iphoneos|iphonesimulator'
```

If `xcodebuild -version` complains that the active developer directory is the Command Line Tools,
you installed the tools rather than Xcode — the `xcode-select` line above fixes it. Add an iOS
simulator runtime if you do not have one (Xcode → Settings → Components, or let the first build
offer to download it). `Scripts/ci.sh probe` prints the toolchain, SDKs and runtimes in one go.

## 2. XcodeGen, clone, generate

```bash
brew install xcodegen
git clone https://github.com/9qhfghxgfy-afk/cairn.git
cd cairn
xcodegen generate
open Cairn.xcodeproj
```

`Cairn.xcodeproj` is **generated and git-ignored**. Never hand-edit it: edit `project.yml` and run
`xcodegen generate` again. XcodeGen is not preinstalled on the CI runners either, so `ci.sh`
installs it there if it is missing.

## 3. Signing: put your Team ID in `Config/Local.xcconfig`

A free Personal Team can sign a build for your own device, and that is all this project needs.
Your Team ID is personal, so it never goes in a tracked file:

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Get the Team ID from Xcode → Settings → Accounts → add your Apple ID → select it → **Show
Details** → Team ID. A free account is listed as *Personal Team*, and that is the team you want.
Put it in `Config/Local.xcconfig` — the value below is the placeholder, which is what the guards
allow in any tracked file; in your own copy it is your 10-character ID:

```
DEVELOPMENT_TEAM = XXXXXXXXXX
```

Optionally set a bundle id of your own so your build cannot collide with anyone else's copy of this
app:

```
CAIRN_BUNDLE_ID = com.example.you.cairn
```

The chain that makes this work is three lines long and worth understanding: `Config/Signing.xcconfig`
sets the default `CAIRN_BUNDLE_ID` and then `#include? "Local.xcconfig"` — the `?` is Apple's
*optional* include, so the settings are picked up when the file exists and skipped when it does not.
`project.yml` points both targets at that xcconfig through `configFiles:`, and the test bundle id is
derived as `$(CAIRN_BUNDLE_ID).tests`, so a personal override moves the app and its tests together
and they cannot collide. **CI has no `Local.xcconfig`**, and its commands pass
`CODE_SIGNING_ALLOWED=NO`, so CI keeps building unsigned exactly as it did before.

Two guards keep the arrangement honest:

- `Config/Local.xcconfig` is git-ignored, and `Scripts/check-signing.sh` fails CI if a real
  `DEVELOPMENT_TEAM` value, an Apple-ID-stamped signing identity, or a pinned provisioning profile
  appears in any tracked file. The tracked template carries only the placeholder `XXXXXXXXXX`.
- A device build deliberately does **not** pass `CODE_SIGNING_ALLOWED=NO`. Without a Team ID it
  fails with a signing error, which is the signal you want, rather than quietly producing a binary
  that cannot install.

## 4. The local commands

`Scripts/ci.sh` is the local equivalent of CI — same sequence, same order, same flags:

```bash
Scripts/ci.sh guards    # privacy guards only; seconds; needs no Xcode
Scripts/ci.sh hosts     # both pure-Swift suites on the macOS host
Scripts/ci.sh build     # generate + build for the simulator
Scripts/ci.sh test      # generate + the full suite on the iPhone 17 simulator
Scripts/ci.sh device    # generate + build for a real iPhone, signed with your Team ID
Scripts/ci.sh all       # everything CI runs, in CI's order — this is the pre-commit check
Scripts/ci.sh probe     # which Xcode, SDKs and simulator runtimes this Mac actually has
```

The same commands spelled out, for when you would rather run them yourself:

```bash
xcodegen generate

# Build for the simulator, unsigned, exactly as CI does.
xcodebuild -project Cairn.xcodeproj -scheme Cairn \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO build

# The full suite on the simulator CI uses.
xcodebuild -project Cairn.xcodeproj -scheme Cairn \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -derivedDataPath DerivedData \
  -resultBundlePath ResultBundles/Cairn.xcresult \
  CODE_SIGNING_ALLOWED=NO test

# A real iPhone, signed with the Team ID from Config/Local.xcconfig. There is no
# CODE_SIGNING_ALLOWED=NO here on purpose: without a Team ID this should fail loudly rather than
# quietly produce a binary that cannot install.
xcodebuild -project Cairn.xcodeproj -scheme Cairn \
  -destination 'generic/platform=iOS' \
  -derivedDataPath DerivedData \
  build
```

The simulator destination is pinned to the runtime CI uses. If this Mac does not have the iOS 26.5
runtime, drop the pin instead of installing a second runtime:

```bash
xcrun simctl list runtimes
SIMULATOR_OS= Scripts/ci.sh test      # iPhone 17, newest available runtime
```

The fast inner loop, when you are only inside the pure domain package, is
`swift test --package-path Packages/CairnChatDomain` — seconds, no simulator, no generated project.

## 5. Run it on the iPhone with a free Personal Team

No paid developer account is needed to run this on your own device.

1. **Add your Apple ID to Xcode**: Settings (`,`) → Accounts → `+` → Apple ID. A free account shows
   up as *Personal Team*. There is nothing else to buy.
2. **Put the Team ID in `Config/Local.xcconfig`** (section 3). You do not need to re-run
   `xcodegen generate` after editing an xcconfig — `xcodebuild` reads it at build time — but do
   re-run it whenever `project.yml` changes.
3. **Plug the iPhone in over USB**, unlock it, and tap **Trust** on the phone.
4. **Enable Developer Mode** on the phone: Settings → Privacy & Security → **Developer Mode**. That
   switch only appears once the phone has actually been talked to by Xcode — a build attempt, or
   Window → Devices and Simulators. Turn it on, let the phone restart, and confirm the prompt again
   after the restart.
5. **Run it**: pick the iPhone as the destination and press Run. The first attempt spends a minute
   *Registering for development* while Xcode creates a free provisioning profile for the bundle id.
   From the shell it is `Scripts/ci.sh device`.
6. If the app refuses to launch, check Settings → General → VPN & Device Management and trust the
   developer certificate there. For a build Xcode just installed this is rarely needed; it matters
   when a profile was installed by hand.

What a free team costs you, and what to do about it:

- **The signature expires after 7 days.** A free provisioning profile is short-lived, so after a
  week the app stops launching with an unusable-signature error. Re-run from Xcode (or
  `Scripts/ci.sh device`) and it is good for another week. Make it a weekly habit, or re-run just
  before the session you actually care about.
- **A free team can only create a few App IDs** — the number people report is three, and Xcode tells
  you when you reach it. Keep **one** `CAIRN_BUNDLE_ID` instead of minting a new identifier for
  every experiment; if the slots are full, clear the spares under Settings → Accounts → Manage
  Settings → Identifiers.
- **Some capabilities need a paid account** — push notifications and the rest of the services that
  talk to Apple's servers. Cairn asks for none of them, which is why a free team is enough.
- **Increased Memory Limit is the open question**, and it is deliberately *not* changed here: the
  files under `Entitlements/` stay exactly as they are until the free-team test has been run in
  Xcode and the result recorded in `ROADMAP.md`. Do not add the entitlement on the assumption that
  a free team can grant it.

## 6. Which check is which

- **Local Xcode is the loop.** Run `Scripts/ci.sh all` before committing. If something is broken you
  want to know in the next minute, not after a runner picks the job up.
- **CI is the second check.** It still runs on every push: privacy guards, the host suites, the
  generated-project build, and the full simulator suite on iPhone 17 / iOS 26.5, plus the nightly
  Xcode 27 forward-compatibility probe. A milestone is still only claimed with a green CI run
  number, because CI is the one environment that is not this laptop.
- **When local and CI disagree, Xcode versions are the first suspect.** `Scripts/ci.sh probe` prints
  what this machine has; the CI log prints the pinned 26.6. Newer is not better for a gate — it just
  means your local result is not the gate's result.
- Do not dispatch `ipa.yml` unless you actually need an IPA for the Windows/Sideloadly fallback in
  `docs/INSTALL.md`. On a Mac there is no reason to build one.
