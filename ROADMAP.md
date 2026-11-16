# ROADMAP — Cairn

Status legend: `done` = green CI run cited · `in-progress` · `todo` · `blocked:<reason>`

Gate for every milestone (from `.clinerules`):
1. `swift test --package-path Packages/CairnChatDomain`
2. `xcodegen generate` → `xcodebuild build` → `xcodebuild test` on iPhone 17 / iOS 26.5
3. `Scripts/ci.sh guards` passes — `check-logging.sh`, `check-ats.sh`, `check-hostname.sh`,
   `check-signing.sh`, and `test-guards.sh` (the guards' own self-test)
4. `ROADMAP.md` status updated in the same commit, citing the CI run number

| # | Milestone | Status | CI run |
|---|---|---|---|
| 0 | Repo + CI lane | **done** | [43684016580](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/43684016580) — first lane run |
| 1 | Shell + mock streaming loop | **done** — all gates green on `1e7e250` | [43685125186](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/43685125186) |
| 2 | Remote providers | **CI-verified only** — all gates green on `a5466dd`; re-verified on `b58a916` after the networking reversal and on `450f602` after the Mac build-loop change. The 10-line device checklist under M2 is what closes it | [43764696840](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/43764696840), [43771679253](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/43771679253), [43795195812](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/43795195812) |
| 3 | On-device inference + memory guardrails | todo | |
| 4 | Hybrid Parallel & Synthesized engine | todo | |
| 5 | Advanced controls, interruption recovery, export/import | todo | |
| 6 | Local RAG, vision, web search, voice | todo | |
| 7 | Parity backlog | todo (per-item approval) | |

## Decisions (durable — update here, not in chat)

Recorded 2026-11-14. These supersede anything older in the repo.

- **Development machine and build loop (2026-11-15).** The development machine is now a **MacBook
  Pro (Apple Silicon)** on macOS 26.x with Xcode installed, 48 GB unified memory, no paid Apple
  developer account, repo still public.
  - **Local Xcode is the primary build loop; CI is a second check, not the way to learn that code
    compiles.** Run `Scripts/ci.sh` locally — `guards`, `hosts`, `build`, `test`, `all`, `probe`,
    `device` — because that is the same sequence CI runs. `device` needs the iPhone connected to
    the Mac, and that is what M2 actually needs.
  - A milestone is still closed only with a green CI run cited on the commit: CI is the environment
    that is not this laptop, and it still runs the whole pipeline on every push.
  - On a fresh Mac, run `Scripts/ci.sh probe` once and record what it prints. It compares local
    macOS and Xcode with the CI pin (runner `macos-26`, Xcode selected to **26.6** in the workflow).
    If the Mac is ahead of the pin — which is the expected case — that is a divergence to **record
    here**, not to fix. Never bump the pin because something builds locally; only a green CI run on
    the new version moves it, and the nightly Xcode 27 probe stays informational.
  - 48 GB changes what is worth testing in M3: bigger on-device models are realistic and there is
    more room for a second resident model. It changes no budget code — `os_proc_available_memory()`
    is still the per-process limit on the iPhone, and the iPhone is the target.
  - The Mac is on the **same tailnet** as the inference machine (same WireGuard router, not another
    VPN product). This adds no requirement and no app: `docs/SERVERS.md` notes only that a Mac on
    the tailnet can reach a served model over the tunnel for testing, and nothing else may change.
    No shipped code may assume any VPN is installed, and a Mac-only debug convenience must not leak
    into shipped behaviour.
  - **Signing is configured by config files, never by hand.** `Config/Signing.xcconfig` is tracked
    and holds no identity; it does `#include? Local.xcconfig`, which each machine keeps locally,
    git-ignored, with `DEVELOPMENT_TEAM` and `CODE_SIGN_STYLE`. CI has no `Local.xcconfig`, so CI
    builds unsigned — no conditional logic anywhere. `project.yml` carries no Team ID, and
    `Scripts/check-signing.sh` fails CI if a Team ID, an Apple-ID-stamped identity, or a pinned
    profile appears in a tracked file. Set a device build destination in Xcode by hand or with
    `xcodebuild -destination`; do not put a destination in `project.yml`.
  - **One xcconfig, always relative.** Both targets point at `Config/Signing.xcconfig`; no xcconfig
    includes another one to share settings, and no include ever uses a `$(SRCROOT)` path — Xcode does
    not resolve it while reading an include, and CI proved that the hard way (run 43794042407, see the
    CI record under M2). A `$(SRCROOT)` path inside the *optional* include would not even fail: it
    would silently drop the Team ID.
- **Distribution / signing.** Free Apple ID (Personal Team). The primary install path is now **Xcode
  on the Mac** — run on the connected device, or Archive → Distribute → *Direct Distribution* to
  the device. The fallback, for when the Mac is not at hand, is an **unsigned device IPA** built by
  CI (`ipa.yml`, workflow_dispatch only) → signed on
  the Windows machine with **Sideloadly** (v0.71+, Windows builds, iOS 7–27+
  supported) using the free Apple ID. Apple's free-account limits: 7-day signing expiry
  (Sideloadly's auto-refresh daemon re-signs near expiry while the PC can reach the
  device over USB or Wi-Fi), at most 3 sideloaded apps active per device, ~10 App IDs
  created per year. No App Store or TestFlight unless the paid Apple Developer Program
  is joined later; the Release configuration stays App Store-clean either way — exactly one ATS
  key (`NSAllowsLocalNetworking`, which narrows rather than widens) and no private APIs.
- **Entitlements.** `com.apple.developer.kernel.increased-memory-limit` is treated as
  **unavailable**: free-Apple-ID signing tools cannot attach custom entitlements
  (Sideloadly's custom-entitlement support is Apple Developer Program only; extended
  virtual addressing is paid-only). M3 must work **with and without** the entitlement;
  confirm availability by measuring `os_proc_available_memory()` on the physical device
  in M3 — never trust community reports. The app must never *require* an entitlement.
- **Networking (2026-11-15, superseding the 2026-11-14 mesh-VPN-only rule).** A server the
  user runs is reached over **plain `http://` at its private address** — a LAN IPv4 literal, or
  that same private address through **the router's own WireGuard server**. No third-party VPN
  product, no mesh network, no VPN DNS name, no HTTPS requirement, no certificate management.
  Nothing beyond the user's own router belongs to this plan, and no code, doc, or test may
  assume a VPN product is installed. Two facts carry this:
  - Apple's ATS scope: ATS "applies only to connections made to public host names", and the
    system provides no ATS protection for **IP addresses**, **unqualified host names**, or
    **`.local` hosts** (Cocoa Keys, *Availability of ATS for Remote and Local Connections*).
    A private IP literal is therefore outside ATS entirely and needs no exception. The
    2026-11-14 reasoning that a LAN IP over HTTP was "impossible via exceptions" mistook
    "NSExceptionDomains cannot match IP literals" for "IP literals are unreachable"; the
    first is true, the second is not.
  - When away from home, **the tunnel is the security layer**. WireGuard encrypts the path
    end to end and the tunnel is the access control, so TLS on top would encrypt twice and
    add a certificate to manage for no security gain.
  Exactly one ATS key ships: **`NSAllowsLocalNetworking = true`**, which covers the one
  remaining case ATS does police — a `.local` or unqualified host *name*. Apple states that
  when this key is YES ATS ignores `NSAllowsArbitraryLoads`, so declaring it **narrows** the
  app's ATS posture rather than widening it. `Scripts/check-ats.sh` now enforces that exact
  shape: the key present and true, and no `NSAllowsArbitraryLoads*` / `NSExceptionDomains`.
  A **public-internet** profile still requires `https://` plus the outbound opt-in, enforced
  in code (`NetworkClass.allowsPlaintext` → profile validation → connection tester) and
  unit-tested — never by an ATS hole. Plaintext always carries a visible `Plaintext` badge.
  iOS's **Local Network** permission is now load-bearing, not cosmetic: the first request to a
  LAN address prompts, and a denial breaks the connection. Bonjour discovery stays in M7.
- **Hostname and address policy (extended 2026-11-15).** No real hostname **and no real
  address** belonging to the user's own network ever appears in the repo, commits, tests, docs,
  screenshots, or CI logs — not a VPN DNS name, not a router's dynamic-DNS name, not a LAN
  address. Docs and tests use documented placeholders only: `your-host.your-vpn.ts.net` is the
  single allowed `*.ts.net` value, `<your-router-hostname>` stands in prose, and addresses come
  from the example set `Scripts/check-hostname.sh` allow-lists. Cairn dials the **private**
  address through the tunnel and never the public endpoint, so a router hostname has no reason to
  exist in this repository at all. The guard now also rejects a **private IP literal** outside
  that allow-list, which is the rule that actually catches a real LAN or tunnel address pasted in
  by mistake.
- **Test device.** iPhone 15 Pro on **iOS 26.2** (8 GB RAM per Apple's specs — confirm
  on device). Do not assume iOS 27. The CI simulator lane stays iPhone 17 / iOS 26.5.
- **CI lane.** `macos-26` + Xcode 26.6 pinned (SDK ceiling iOS 26.5), deployment target
  iOS 26.0, repo stays **public** (that is what keeps macOS minutes free),
  `actions/checkout@v7` + `actions/upload-artifact@v7` (clears the Node 20 deprecation
  warnings).

### Housekeeping verification (2026-11-15)

| Item | Run | Commit | Result |
|---|---|---|---|
| M1 closure + README fix + Decisions + zero-ATS policy + actions v7 + check-hostname guard | [43687374128](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/43687374128) CI #5 | `af510dd` | ✅ green |
| IPA pipeline first attempt | 43687522048 IPA #1 | `af510dd` | ❌ `lipo` argument-order bug in the verify step (build + packaging were fine) |
| CI after the lipo fix | [43687758566](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/43687758566) CI #6 | `e158735` | ✅ green (guards job now runs all three checks) |
| Unsigned device IPA | [43687776681](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/43687776681) IPA #2 | `e158735` | ✅ green — artifact `cairn-unsigned-ipa` (~313 KB, arm64, unsigned, Info.plist valid) |
| Sideloadly install on the iPhone | — | — | ⏳ user action pending — steps in `docs/INSTALL.md` |

## Milestone 0 — Repo + CI lane · done

Repo scaffold, `project.yml`, three SwiftPM packages, pinned CI (macos-26 + Xcode 26.6,
iPhone 17 / iOS 26.5), XcodeGen installed in CI, privacy guards on a cheap Linux job,
nightly `xcode-27` probe. Acceptance: CI runs on push and the probe step prints Xcode,
SDK, and simulator runtime versions. Public repo, so macOS minutes cost nothing.

## Milestone 1 — Buildable shell + mock streaming loop · done

Files created:

- `project.yml`, `.gitattributes`, `.gitignore`, `.clinerules`
- `Packages/CairnChatDomain` — `StreamChunk`, `Provider`, `ChatModels`, `ChatTreeQueries`,
  `ChatTreeMutations`, `ChatStore`, `EphemeralStore`, `StreamAccumulator`,
  `MockStreamingProvider`, `ChatSessionModel` (+`TreeOps`, +`Streaming`), `ChatWorkspace`
- `Packages/CairnPersistence` — `Records`, `Mapping`, `SwiftDataStore`
- `Packages/CairnAppUI` — `CairnIdentity`, `MessageRow` (+`Controls`), `ChatScreen`
  (+`Menus`), `CairnRootView`
- `App/CairnApp.swift`
- Tests: `ChatTreeBranchTests`, `ChatTreeQueryTests`, `StreamAccumulatorTests`,
  `ChatSessionStreamingTests`, `ChatSessionBranchTests`, `SwiftDataStoreTests`,
  `SwiftDataPayloadAndWorkspaceTests`
- `.github/workflows/ci.yml`, `nightly-xcode27.yml`, `Scripts/{ci,check-logging,check-ats}.sh`

Acceptance criteria:

1. The generated project builds for the iOS Simulator with no signing.
2. Sending a message appends a user node then an assistant node, streams tokens, and
   records real `.metrics` (tok/s, tokens, finish reason).
3. The reasoning panel appears only for the thinking-capable mock and disappears when
   thinking is off.
4. Stop mid-stream keeps partial text and marks the node `.cancelled` in memory **and**
   in the store.
5. Regenerate creates a sibling; `< 1 / N >` steps between branches; edit appends a
   sibling and leaves the old branch walkable.
6. Temporary chat is backed by `EphemeralStore`, and `SwiftDataStore` refuses temporary
   conversations.
7. Unit + SwiftData tests green on iPhone 17 / iOS 26.5.

Known gaps at M1: no AppIcon asset set; hybrid modes visible but disabled; no network code
at all, so no Local Network prompt and no ATS surface yet.

### Verification record (run 43684585956, `47f1c7e`)

| Gate | Result |
|---|---|
| Privacy guards (logging + ATS) | ✅ pass |
| `swift test` on macOS | ✅ pass (after 2 fixes) |
| `xcodegen generate` | ✅ pass |
| `xcodebuild build` (iOS Simulator, unsigned) | ✅ pass |
| `xcodebuild test` on iPhone 17 / iOS 26.5 | ❌ 1 failure — all SwiftData tests green |

Bugs this loop actually found (not test-noise):

1. **Cancelled turns reported `.complete`.** `AsyncThrowingStream` can end iteration
   cleanly on cancellation instead of throwing, so a truncated answer was marked
   finished. Fixed by checking `Task.isCancelled` / `.cancelling` after the loop.
2. **Dropped-array footgun.** `ChatTree` value-in/value-out let fixtures silently lose
   parent nodes. Fixed by adding `ChatDraftTree`, which keeps the array on every mutation.
3. **Stale conversation on rebind.** `ChatWorkspace.select()` rebound from the cached
   `conversations` snapshot, whose `activeLeafID` predated the last send — the transcript
   came back empty. Fixed to re-read the row: the store is the source of truth, cached
   lists are display snapshots only.

### Final green run — M1 closed (run 43685125186, commit `1e7e2506`)

| Gate | Result |
|---|---|
| Privacy guards (logging + ATS) | ✅ pass |
| `swift test` on macOS | ✅ pass |
| `xcodegen generate` | ✅ pass |
| `xcodebuild build` (iOS Simulator, unsigned) | ✅ pass |
| `xcodebuild test` on iPhone 17 / iOS 26.5 | ✅ pass — the rebind fix cleared the last failure |

M1 is **done** on the HEAD commit, all five gates green. No M1 on-device checklist is
required (M1 is simulator-provable; device checklists arrive at the end of M3 and M5).

## Milestone 2 — Remote providers (Ollama, OpenAI-compatible / LM Studio) · done

Scope corrected 2026-11-15 to match **Decisions** (the original body below predated the
zero-ATS-exception and defer-Bonjour decisions and has been rewritten, not silently ignored):

- `Packages/CairnChatDomain/Remote` — pure, host-testable contracts: `ServerProfile`
  (+ `ServerProfileKind`, validation, canonical URL), `NetworkClassRouting` (RFC 1918 /
  `.local` / unqualified / loopback / `*.ts.net` / 100.64.0.0/10), `LineStreamParser`
  (byte-level SSE + NDJSON framing), `OllamaCodec`, `OpenAICodec`, `RemoteTestReport`
  (+ `RemoteTesting`, `ServerProfileStoring`, `SecretStoring`, `RemoteModelManaging`
  boundaries so the UI never imports a networking module), `ProviderRegistry`.
- `Packages/CairnProviderRemote` — URLSession streaming (delegate transport, explicit
  task cancellation), `RemoteChatProvider` per wire protocol, model management
  (`/api/tags`, `/api/ps`, `/api/pull`, `/api/delete`; listing only on OpenAI-compatible),
  `RemoteConnectionTester` (typed, teach-the-fix outcomes), `KeychainSecretStore`
  (`.afterFirstUnlockThisDeviceOnly`, injectable operator so CI never touches a real keychain).
- `CairnPersistence` — `ServerProfileRecord`, with `SwiftDataStore` conforming to
  `ServerProfileStoring` in `SwiftDataStore+Profiles`; headers as JSON in SwiftData, never
  logged; token never leaves Keychain.
- `CairnAppUI` — `ServersModel` view model + profile list, profile editor (name, kind, URL,
  Keychain token, custom headers, plaintext accepted on a private address and refused on a
  public-internet host with an explanation, public-internet opt-in, `Plaintext` badge),
  capability-gated model management (Pull/Delete/Loaded models on
  Ollama only; disabled with a reason on OpenAI-compatible), persistent `NetworkBadge`, and a
  `CredentialInClearWarning` wherever a bearer token is set on an `http://` profile.
- Optional **Ollama Cloud** profile: created only on explicit opt-in, `.publicInternet`,
  labelled as internet, off by default.
- `docs/SERVERS.md` — the server-access guide, written 2026-11-15: binding the server so the LAN
  can reach it, an optional API key, firewall rules scoped to the LAN subnet with **no port
  forwarding**, and the WireGuard client config whose `AllowedIPs` must include the LAN subnet.
  Placeholders only, and only the addresses `Scripts/check-hostname.sh` sanctions. The original
  plan for this file — a mesh-VPN + HTTPS install guide — was superseded on 2026-11-15 by the
  networking decision, and the guide was written against the new one instead.
- **Dropped from M2** (superseded by Decisions): Bonjour discovery and `NSBonjourServices`
  → M7; Debug-only scoped `NSExceptionDomains` and the per-config plist split → never;
  the VPN-provided-HTTPS requirement → superseded on 2026-11-15 by private plaintext
  (LAN address, or that address through the router's WireGuard tunnel).

Acceptance criteria:

1. All five CI gates green: guards, `swift test` (domain + remote packages), `xcodegen`,
   `xcodebuild build`, `xcodebuild test` on iPhone 17 / iOS 26.5.
2. Parser/codec/profile tests cover split chunk boundaries, mid-multibyte UTF-8, `[DONE]`,
   malformed lines, mid-stream errors, cancellation, real-usage-only metrics, network
   classification, private-plaintext-accepted / public-plaintext-refused validation,
   reserved-header rejection.
3. Provider tests against a stub transport: Ollama NDJSON and OpenAI SSE end to end, 401/500
   mapping, tester outcomes, plus a real loopback (127.0.0.1) stub server.
4. SwiftData profile round trip incl. custom headers and `hasBearerToken`; Keychain logic
   covered through a fake operator (real Keychain is device-only).
5. UI: profile editor + tester + model management compile and run in the app; a public host
   over http is rejected with an explanation, a private host over http saves and carries the
   `Plaintext` badge; OpenAI-compatible servers expose no Pull/Delete.
6. `check-ats.sh` proves the single permitted ATS key and no other; `check-hostname.sh`
   proves no real private hostname (a VPN DNS name **or** a dynamic-DNS name) is tracked, and since
   2026-11-15 also that no private IP outside the documented example set is tracked.

**M2 is CI-verified only.** No stub test may be reported as a real LAN or VPN connection.

### Implementation and verification record (2026-11-15, CI run [43764696840](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/43764696840) on `a5466dd`)

Everything the milestone scope names is now in the tree, and this record says plainly what is
proven and what is not:

- `Packages/CairnProviderRemote` (source, 17 files): `RemoteTransport` (delegate transport —
  bytes only, never a `bytes:` publisher, because a publisher cannot be cancelled cleanly),
  `RemoteByteStream` with an explicit `abandon` closure so Stop closes the task even when a
  transport is blocked waiting for the next byte, `RemoteChatPipeline` (a `URLSessionDataDelegate`
  hands raw chunks to `LineStreamParser`, so a chunk may end anywhere, including inside a
  multibyte character), `RemoteChatProvider`, `RemoteModelService`, `RemoteConnectionTester`,
  `RemoteProviderFactory`, `KeychainSecretStore` over an injectable `KeychainOperating`,
  `SecurityKeychainOperator` (`.afterFirstUnlockThisDeviceOnly`, no `kSecUseDataProtectionKeychain`).
- Tests, all host-only (`Scripts/ci.sh remote`): framing across chunk splits and mid-accent
  byte splits, unterminated final line, in-band `{"error"}` on a 200, `[DONE]`, usage-only
  metrics (no metrics at all when the server reports no counts), 401/500 mapping, bearer
  header from the Keychain, credential headers dropped defensively, catalog decoding for both
  dialects, opt-in gating, tester outcomes with their teaching hints, Keychain policy through
  a fake operator, and a real `NWListener` stub on 127.0.0.1 for the delegate, status mapping,
  and Stop-against-a-live-socket. Loopback only: no test reaches the internet.
- `CairnPersistence`: `ServerProfileRecord` (headers as JSON, `hasBearerToken` flag, **no
  token column**) plus `SwiftDataStore+Profiles`; covered in the simulator suite.
- `CairnAppUI`: `ServersModel` + `ServersView` + `ServerProfileEditor` (+`Sections`, `Row`),
  wired in `CairnApp` through `ProviderRegistry` and `RemoteProviderFactory`; the app test
  suite covers validation refusal, token-only-in-Keychain, delete-removes-the-secret, and
  disabled-profile-leaves-the-engine-list.
- CI: `Scripts/ci.sh` gained `remote` and `hosts` targets, and the host job runs both host
  suites. Run #15: guards green; 59 domain tests green; the remote package suite green against
  the stub transport and the 127.0.0.1 listener; xcodegen + simulator build green; 22 simulator
  tests green with no failures. `check-hostname.sh` also caught two M1 test fixtures that used
  invented VPN DNS hosts instead of the one allowed placeholder; both now use the placeholder.

What CI cannot prove, and what therefore stays unclaimed: Keychain behaviour against a real
keychain (device-only — the policy is covered here through a fake operator), and any real
connection to the user's own server over LAN or VPN. The server facts that used to block the
latter are resolved (see **Probe of the user's real server + transport reversal**); what still
cannot be claimed from a runner is the Local Network prompt, the WireGuard route into the LAN
subnet, and streaming over that tunnel. The loopback stub is not a substitute for any of it.

### Final green run — M2 closed (run 43764696840, commit `a5466dd`)

| Gate | Result |
|---|---|
| Privacy guards (logging + ATS + hostname) | ✅ pass |
| `swift test` on macOS — domain package | ✅ pass (59 tests) |
| `swift test` on macOS — `CairnProviderRemote` | ✅ pass (34 tests, incl. the 127.0.0.1 `NWListener` stub) |
| `xcodegen generate` | ✅ pass |
| `xcodebuild build` (iOS Simulator, unsigned) | ✅ pass |
| `xcodebuild test` on iPhone 17 / iOS 26.5 | ✅ pass (22 tests) |

It took eleven failing runs to get there, and the fixes were mostly real defects rather than
test noise:

1. **Two OpenAI wire keys were camelCase.** `OpenAICodec` serialized `stream_options` as
   `{"includeUsage":true}` and the image part as `{"imageURL":{…}}`. Both are accepted by the
   server and then ignored, which is worse than an error: usage chunks never arrive, so every
   OpenAI-compatible turn would report *no usage reported* forever, and image attachments would
   silently vanish. Now mapped to `include_usage` / `image_url`.
2. **A streaming tail can be a complete line.** The byte-at-a-time codec test built a body with
   no trailing newline and never drained `takeTrailingPartialLine()`, so its final `done` line
   was dropped. The production pipeline does drain the tail; the fixture now matches it instead
   of quietly requiring a trailing newline that real servers do not always send.
3. **Main-actor isolation was assumed, not written.** `ServersModel` took the engine builder as a
   nonisolated function type while the app hands it a `@MainActor` factory method, and the
   profile editor and row call into `ServersModel` from members that are not `body`. Both views
   are now `@MainActor`, and the builder carries its isolation in its type.
4. **The editor never had state.** Every editable field was assigned
   `State(initialValue:)` in `init` while declared as a plain `var`, so `$name`, `$urlString`,
   and `$headerRows` referred to storage that did not exist.
5. **`any Error` is not `Sendable`.** The failing-transport test double stored an error value in
   a `Sendable` struct; it stores a `URLError.Code` and builds the error at use.

Plus the ordinary compile corrections CI caught in code written on a machine with no Swift
toolchain: `flatMap` cannot infer across differently shaped `switch` arms, `URLError.Code` has
no `cannotParseURL`, a throwing `decodeVersion` call had no `try`, `KeychainQuery` needed
`Hashable` to key a dictionary, `NWConnection.receive` takes `maximumLength`, and a stub `init`
had a declaration with no body. One test expectation was wrong too: it expected the mock engine
to survive a publish while passing no `baseEngines`, so publishing correctly dropped it.

The honest limitation of this loop: those eleven runs were compile-and-unit feedback, not
behaviour proof against a server. The wire keys in item 1 are exactly the class of defect that
unit tests against a stub cannot catch, and they were caught by asserting our own serialized
body. Whether Cairn really talks to the user's own server is still untested on a device and is
the first thing the device checklist must establish.

### Probe of the user's real server + transport reversal (2026-11-15)

The server facts listed under **Blocked on the user** are resolved, and they invalidated the
M2 networking decision. Findings from probing the server directly over the LAN (addresses and
hostnames stay out of this file by policy):

1. **The engine is llama.cpp-style, not Ollama.** `GET /v1/models` answers with **both** an
   OpenAI-shaped `data[]` array and an Ollama-shaped `models[]` array, while `GET /api/tags`
   and `GET /api/version` return `404` with `not_found_error`. So the Ollama dialect's version
   and tags endpoints do not exist: a profile set to **Ollama** fails the connection test on an
   endpoint the server has never had. The profile default is now **OpenAI-compatible** and the
   editor's empty-state text says why.
2. **Chat completions stream correctly** on `/v1/chat/completions` with `stream: true`,
   including a `usage` chunk under `include_usage` — which is exactly the wire key the M2
   green run fixed (item 1 of the defect list). The fix is now known to matter against a real
   server, not only against a stub.
3. **The server is reachable at its LAN IPv4 address over plain http**, which is what the
   2026-11-14 decision said was unreachable. That is the reversal recorded in **Decisions**:
   Apple's ATS scope excludes IP addresses, unqualified names, and `.local` hosts, and the
   router's WireGuard tunnel — not TLS — is the protection when away from home. No third-party VPN product,
   no VPN DNS name, and no HTTPS-on-the-tunnel requirement survived that reversal.
4. **A single-model server ignores the `model` field it is sent**, so a wrong model id produces
   no error, only a surprise later. Model ids must be chosen from the fetched list; typing one
   from memory is not a supported workflow.

Code and guard changes that followed, all verified locally (no Swift toolchain here, so CI is
the compile gate): `NetworkClass.allowsPlaintext` as the single rule; profile canonicalization
and validation accept private plaintext and refuse public plaintext with a distinct
`plaintextPublicInternet` error; the connection tester refuses only public plaintext;
`PlaintextBadge` on rows and the editor; every VPN-DNS-specific error hint rewritten
to speak in terms of address, port, route, and VPN; `check-ats.sh` rewritten to require the one
permitted key and reject any other; `check-hostname.sh` extended to catch a router's dynamic-DNS hostname
as well as a VPN DNS name.

Guard verification run locally (8 scenarios, all behaving as specified): spec-only checkout
passes; generated plist with the one key passes; a plist adding `NSAllowsArbitraryLoads`, a
plist setting the key `false`, and a plist with `NSExceptionDomains` each fail; a spec with the
key deleted or swapped to the blanket exception each fail; the hostname and logging guards pass
on the current tree. Two defects were caught by that harness before committing: the guard
grepped comments, so its own explanatory comment naming a banned key failed the build, and the
`guards` job runs on Ubuntu where `App/Info.plist` is never generated — the guard now falls
back to `project.yml` there, and an extra step re-runs it on the generated plist in the build
job.

Still unclaimed: any on-device result. The Local Network prompt, WireGuard routing from the
tunnel into the LAN subnet, and streaming over the tunnel are device facts, and `AllowedIPs`
must include the LAN subnet for the private address to be routable at all.

### M2 device checklist — run this on the iPhone to close M2 honestly

Each line states what it proves. Anything not checked stays unclaimed; a pass on one line is
not evidence for the next.

1. **Build and run from Xcode on the Mac** — ⌘R with the iPhone connected (from the Windows machine
   the fallback is the CI artifact sideloaded with Sideloadly). Proves the signing path still works
   on the route actually used.
2. **Servers → Add server → OpenAI-compatible → `http://<lan-address>:<port>` → Save.**
   Must save, not be refused, and the row must show the **LAN** badge and the **Plaintext**
   badge. A refusal here means the private-address rule regressed.
3. **Allow the Local Network prompt** iOS raises on the first request. Deny it once, confirm
   Test reports the connection-refused hint, then re-enable in Settings and continue. This
   proves the hint teaches the right fix — the one thing CI cannot observe.
4. **Test** on the row → expect *Connected* with a model count. A `404` on an Ollama endpoint
   means the profile was set to Ollama on a llama.cpp server (see probe finding 1).
5. **Models** → the model appears in the list. Choose it from the list; typing an id is not a
   supported path on a single-model server.
6. **Send a prompt on that server.** Tokens must stream with a tok/s figure **and** a usage
   count at the end. No usage reported means the `include_usage` wire key regressed.
7. **Stop mid-stream**, then **regenerate**, then **branch** and step `< 1 / N >`. Tree
   behaviour against a real server, not just the mock engine.
8. **Turn on the WireGuard tunnel from outside the home network** (or with `AllowedIPs`
   covering the LAN subnet) and repeat 4–6 using the **same private address**. Proves the
   tunnel route and that nothing about the app depends on being on the local Wi-Fi.
9. **Away with the tunnel off** → Test must fail with the timeout hint, not hang forever.
10. **Force-quit and relaunch.** The profile, model choice, and the partial stream survive;
    the token is still only in Keychain (`Token in Keychain` label, no token text anywhere).

Any line that fails is a real defect, and its fix belongs in the same milestone. Until 1–10 are
checked on the device, M2 remains CI-verified only.

### CI record for the reversal (2026-11-15, CI run [43771679253](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/43771679253) on `b58a916`)

All three jobs green on the branch push:

- `Privacy guards` (`ubuntu-latest`) — hostname guard (a VPN DNS name plus the new dynamic-DNS
  rule) and the ATS guard. This is the run that proves the guard works from a **spec-only**
  checkout, because the Linux runner has no XcodeGen and therefore no `App/Info.plist`.
- `Host unit tests (macOS)` — domain and remote suites green.
- `Build + test on simulator` (`iPhone 17 / iOS 26.5`) — build green, `Executed 23 tests,
  with 0 failures`. The build job also re-runs the ATS guard against the **generated**
  `Info.plist`, where it reports `ok: the shipped Info.plist sets NSAllowsLocalNetworking =
  true` — the proof that XcodeGen emits exactly the intended key and nothing else, which is
  the part a YAML-only check cannot establish.

Two CI failures came up on the way and both were the guards' own doing, not the policy's: the
ATS guard matched a comment that merely named a banned key (now anchored to real plist/YAML
keys), and it ran on Ubuntu where the generated plist does not exist (it now validates the
spec there). The hostname guard also failed on a literal dynamic-DNS domain written into the new
docs, which is why that rule is now spelled as a regex and the docs name the class rather than
a real hostname.

What this run still does not prove is the device side: the Local Network prompt, the route to
a private address over Wi-Fi and over the WireGuard tunnel, and streaming over that tunnel.
**1–10 above** remain the gate for those.

### CI record for the Mac build loop and the signing config (2026-11-15)

**First, the failure this batch caused, because it is the useful part.** Run
[43794042407](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/43794042407) on `ca853ed` went red
in the simulator job, step 9, **before a single test ran**:

```
could not find included file '$(SRCROOT)/Config/Signing.xcconfig' in search paths
(in target 'CairnTests' from project 'Cairn')
```

The cause was the new signing config itself. `Config/Signing.Tests.xcconfig` chained into
`Config/Signing.xcconfig` with `#include "$(SRCROOT)/Config/Signing.xcconfig"`, and Xcode does not
resolve a `$(SRCROOT)` path while it is reading an include — so the test target never got
`CAIRN_BUNDLE_ID` and the test action refused to start. The app build step passed, which is why the
failure looked like a test problem rather than a config problem. Fixed in `69b7f4f`: that file is
deleted and **both targets point at `Config/Signing.xcconfig` directly**, leaving exactly one include
in the project — the relative `#include? "Local.xcconfig"` — and nothing else for Xcode to miss. The
rule is written into `docs/BUILD-MAC.md` and `project.yml`: never put a `$(SRCROOT)` path in an
xcconfig include, and never let one xcconfig include another to share settings. With a plain
`#include` Xcode stops the build (that is the lucky case); inside `#include?` the same mistake would
silently ignore your Team ID.

**The green record — run
[43795195812](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/43795195812) on `450f602`, all
three jobs green on the branch push:**

- `Privacy guards` (`ubuntu-latest`) — logging, ATS, hostname/address, the new signing-identity
  guard, and `Scripts/test-guards.sh` at **34 planted cases, 0 failures**. The planted set gained a
  second RFC1918 case: an address inside `172.16/12` that is **not** one of the documented examples —
  written in the test as two fragments so neither the test source nor any doc carries the whole
  literal — must be rejected without the guard echoing it, in a tree that also holds the documented
  `172.16.0.1` boundary example, which must still pass. That pair is what proves the allow-list is an
  allow-list rather than a "looks private-ish" test.
- `Host unit tests (macOS)` — domain and remote suites green.
- `Build + test on simulator` (`iPhone 17 / iOS 26.5`, Xcode 26.6) — generated project builds, suite
  runs, and the ATS guard re-checks the generated `Info.plist`. This is the lane that catches what
  neither machine's local checks can: Xcode's own reading of the xcconfig chain, which is precisely
  what broke.

**What is explicitly *not* claimed.** `xcodegen generate`, `xcodebuild build`, `xcodebuild test`, and
`Scripts/ci.sh probe` have never been run on the Mac from this workspace, so: the local Xcode/macOS
version against the CI pin (26.6) is still an **unrecorded divergence**; the local signing path —
`Config/Local.xcconfig` → a signed build on the iPhone — has never been exercised; and the Increased
Memory Limit capability question is untouched. The Mac is the primary loop in the docs now, but it has
not yet been demonstrated as one. M2 stays **CI-verified only**: the 10-line device checklist remains
the gate, and nothing in this batch is on-device-verified or real-network-verified.

Run [43796151531](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/43796151531) closed this batch:
`Privacy guards`, `Host unit tests (macOS)` and `Build + test on simulator` all green on `8ee064e`, the
commit that carries the Mac build-loop docs, the rules entry and the CI record above. The run between
them, [43795785723](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/43795785723) on `ad1bd9f`, ended
`cancelled` — the next push superseded it under the workflow's concurrency rule, which is that rule
working as intended and not a test failure. The Mac is now the documented primary loop; it has still not
been *used* as one from this workspace.


## Plan change (2026-11-15) — LAN plus the router's own WireGuard; the mesh-VPN route is out

Recorded with its date, because this is what Milestone 2 was originally scoped around and the
repository must stop reading as though a mesh VPN were the plan.

- **The decision.** At home the app dials the server's LAN address over plain `http://`. Away
  from home the phone joins the same network with the **WireGuard app** and dials **the same
  private address**. Nothing else belongs to the design: no third-party VPN product, no mesh
  network, no hosted DNS name, no served HTTPS, no certificates to manage.
- **`docs/SERVERS.md`** (`0c0455b`) is the server-side guide for that: binding so the LAN can
  reach the port, an optional API key that belongs in the Keychain-backed token field, firewall
  rules scoped to the LAN subnet with **no port forwarding**, and the WireGuard client config
  whose `AllowedIPs` must cover the LAN subnet. Addresses are placeholders only.
- **Vocabulary** (`8cbedcf`): `NetworkClass.tailnet` became `.privateVPN`; the allowed
  `*.ts.net` placeholder is now `your-host.your-vpn.ts.net`; the mesh-VPN install text is gone
  from `docs/INSTALL.md`, `README.md`, `ARCHITECTURE.md`, `PRD.md`, and `.clinerules`. The
  classification of VPN DNS names and `100.64.0.0/10` is kept on purpose — still private, still
  badged `VPN`, still unit-tested — it is simply no longer the expected route.
- **Hostname and address guard extended** (this commit). `Scripts/check-hostname.sh` now rejects
  three classes: a real mesh-VPN DNS name, a router's dynamic-DNS hostname, and — new — any
  **private IP literal** that is not one of the documented example addresses in its
  `ALLOWED_IPS` (a LAN host and subnet, tunnel addresses, loopback, and the classifier's
  `100.64/10` and `172.16/12` boundary values). Failures print `file:line` only, never the
  matched value, so a CI log cannot leak what it caught. Allow-listed addresses are blanked out
  before the private-range test, so a line holding both an example address and a real one still
  fails — the single-line loophole the old script documented is closed for the IP class.
  Verified locally in Git Bash: prose forms (`192.168.x.x`, `10.x`), every documented example,
  and public or RFC 5737 documentation addresses pass; a real LAN address, a real tunnel
  address, a real `100.64/10` address, a link-local address, a real VPN DNS name, and an
  example-plus-real pair on one line each fail with `file:line` only; the tree passes clean.
- **A token on a plaintext profile now warns** (this commit). `ServerProfile.credentialSentInClear`
  is the single rule — a Keychain-backed token plus an `http://` URL — and both the server row
  and the profile editor show `CredentialInClearWarning` ("Token crosses the network
  unencrypted"). The editor counts a token being typed into the open sheet, and stops warning the
  moment a stored token is removed inside it. Keying a LAN server is legitimate, so this warns
  rather than refuses. Host-level unit test covers token+http (warns), no token (silent), and the
  same key over https (silent).
- **What this still does not claim.** None of it is device proof. The M2 device checklist above
  is unchanged and remains the gate for the Local Network prompt, the tunnel route into the LAN
  subnet, and streaming over that tunnel.

## Milestone 3 — On-device inference + memory guardrails

Foundation Models behind `#available(iOS 26.0, *)` with
`SystemLanguageModel.default.availability` surfaced as an explicit reason (device not
eligible / Apple Intelligence off / model not ready) rather than a silent failure.
Evaluate llama.cpp Swift bindings vs mlx-swift for models Apple's API cannot serve,
isolated in `CairnInferenceNative` (Swift 5 mode). `os_proc_available_memory()` as a
point-in-time estimate plus conservative model + KV-cache sizing for the active context;
graceful load-failure and memory-warning handling; Background URLSession downloads with
pause/resume and SHA-256 verification; storage cleanup; per-chat temperature, top-p,
repeat penalty, context window, max tokens, thinking toggle, system prompt.

**On-device checklist is delivered at the end of M3** — Metal GPU execution, memory
headroom, and download resume cannot be validated on a CI runner.

## Milestone 4 — Hybrid Parallel & Synthesized engine

Four modes per chat or prompt. Parallel via `withTaskGroup` with live tok/s per side.
Synthesized streams both drafts into collapsible panels, then a user-selected synthesizer
lists agreements, disagreements, and unsupported claims and writes one unified answer —
stored as a single synthesized node carrying its drafts. Memory rule enforced: never two
on-device models resident; synthesizer defaults to remote or runs sequentially.

## Milestone 5 — Advanced controls, interruption recovery, export/import

Branch navigation polish, Continue Generation, reasoning panels with elapsed timers,
prompt queueing while streaming, chat search, `.md` plus lossless `.json` (full tree)
export and import, and the background policy in `ARCHITECTURE.md` §9 with
`BGTaskScheduler.shared.supportedResources` checked at runtime (assume no `.gpu` on
iPhone), `beginBackgroundTask` fallback, incremental partial persistence, explicit
Continue / Retry.

**On-device checklist is delivered at the end of M5.**

## Milestone 6 — Local RAG, vision, web search, voice

PDFKit / CSV / Markdown / code chunking with size validation and source citations; vision
attachments only to capability-badged models; `WebSearchProvider` defaulting to a
user-configured SearXNG URL, with the connection tester checking whether JSON output is
enabled and explaining how to turn it on; optional fragile keyless fallbacks flagged with
their terms-of-service risk; client-side tool-calling loop with a readability fetcher;
SpeechAnalyzer / DictationTranscriber on iOS 26+, `SFSpeechRecognizer` below it with
`supportsOnDeviceRecognition` checked and `requiresOnDeviceRecognition = true`, warning
instead of silent cloud recognition; `AVSpeechSynthesizer` output with play/pause/stop,
`AVAudioSession` setup, and interruption handling.

## Milestone 7 — Parity backlog (approval required per item)

On-device image generation, Whisper-class transcription, personas with viewable and
deletable local memory, approval-gated MCP client (draft-then-approve), encrypted local
vault, device-to-device sync, meeting capture.

## Blocked on the user

Resolved facts (device, signing identity, distribution route, repo visibility, server engine
and address) moved to **Decisions** above. Still open:

- On-device proof of the server connection: the iOS Local Network prompt, the WireGuard route
  from the tunnel into the LAN subnet (`AllowedIPs` must cover it), and streaming over that
  tunnel. CI cannot exercise any of these; the checklist under **M2 device checklist** is what
  closes them.
- `increased-memory-limit` availability: assumed unavailable (see Decisions); confirmed
  only by on-device measurement in M3.
- **Increased Memory Limit on a free Personal Team — run this test and report the result.** On the
  Mac: `xcodegen generate`, open `Cairn.xcodeproj`, select the `Cairn` target → **Signing &
  Capabilities** → `+ Capability`, and search for **Increased Memory Limit**. Report two things:
  whether the capability can be added at all (it writes a
  `com.apple.developer.kernel.increased-memory-limit` line into `Cairn.entitlements`), and whether
  the project then still builds and runs on the connected iPhone. **Do not add that entitlement to
  the shipped entitlements file before the test**, and do not treat a successful add as proof it is
  honoured — free Personal Team profiles may accept the key and silently drop it. Until it is
  reported, it stays assumed unavailable, and M3 code must work with **and** without it either way.
- App-icon asset pipeline (the mark is currently code-drawn `CairnMark`).
