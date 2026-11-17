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
| P0 | Zero-paywall guard + parity ledger | **done** — all gates green on `c4f58aa` | [44001146864](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/44001146864) |
| P1 | Servers parity: active-server selection, one-tap switching with per-server last model, `lmStudio`/`ollamaCloud` kinds, guide sheet, user-initiated LAN scan | **done** — code + all five required suites green on `de0ec5a` | [44015633614](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/44015633614) |
| P2 | Per-chat + default configuration, `configured` vs `unset`, capability-filtered payloads, injected context, themes | **done** — code + both new simulator suites and the domain suite green on `823bd86` | [44144881214](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/44144881214) |
| P3–P5 | Parity milestones, ledger in `docs/PARITY.md` | todo (plan approved 2026-11-16) | |

## Decisions (durable — update here, not in chat)

Recorded 2026-11-14. These supersede anything older in the repo.

- **Development machine and build loop (2026-11-15; machine corrected 2026-11-16).** The development
  machine is a **MacBook Pro 13-inch (M1, 2020)** on macOS 27.2.1 with Xcode 27.2, **8 GB** unified
  memory, no paid Apple developer account, repo still public. The "48 GB" recorded on 2026-11-15 was
  wrong — it described a different machine — and nothing may be scoped against headroom this Mac
  does not have.
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
  - 8 GB, not 48, is what this Mac has, so M3's on-device work is tighter here than that note
    implied: one `xcodebuild` process at a time, and simulators shut down after testing. It changes
    no budget code — `os_proc_available_memory()` is still the per-process limit on the iPhone, and
    the iPhone is the target.
  - The Mac reaches the inference machine over the **same home LAN**, and through the **router's own
    WireGuard tunnel** when away — no VPN product and no mesh service is part of the plan. This adds
    no requirement and no app: `docs/SERVERS.md` notes only that a Mac on that LAN or tunnel can
    reach a served model for testing, and nothing else may change.
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
- **Parity program (2026-11-16).** Feature parity with the Reins-class client set is scheduled as
  `P0`–`P5` folded into the existing `M3`–`M7` spine. The ledger of every owed feature, its milestone
  and its verification label is **`docs/PARITY.md`**; it is updated in the same commit as the work.
  Approved sequencing decision: P0 (guards/tooling) and P1 (servers) proceed **while the M2 device
  checklist stays open** — the user runs that 10-item checklist in one batched pass later, so M2 and
  anything touching the network path stays `CI-verified only` until then. No `.reins` import exists
  or is planned; no sample file has been provided. The Reins repository is never read: §3 of the
  parity brief is the only specification, which keeps Cairn out of GPL territory.
- **External API facts verified 2026-11-16, not assumed.** Three assumptions in the brief were wrong,
  and the code must follow the API rather than the brief:
  - **LM Studio is not OpenAI-only.** 0.4.0 ships a native v1 REST API — `GET /api/v1/models`,
    `POST /api/v1/models/load`, `POST /api/v1/models/unload`, `POST /api/v1/models/download`,
    `GET /api/v1/models/download/status`, `POST /api/v1/chat` — alongside OpenAI-compatible `/v1/*`.
    Model lifecycle for LM Studio is therefore real, and a third `ServerProfileKind` is the honest
    model of it. The legacy `/api/v0/*` shape is not to be coded against.
  - **Ollama web search is not automatic.** It is a separate endpoint, `POST https://ollama.com/api/web_search`
    (`query`, optional `max_results`), and it **requires an API key and a free Ollama account**. So
    "cloud models search with no key and no account" cannot be built. The keyless provider serves
    local and standard servers; the cloud route is a key-gated provider that only exists once the
    user supplies a key. Ollama cloud base URLs: `https://ollama.com/api` and `https://ollama.com/v1`.
  - **MLX Swift LM moved repositories.** `MLXLLM`, `MLXLMCommon`, `MLXVLM`, `MLXEmbedders` now live in
    `ml-explore/mlx-swift-lm`, not `mlx-swift-examples`. Its Hugging Face downloader is not a
    background `URLSession`, so Cairn owns download/resume/SHA-256 and hands MLX a local directory.
- **Local toolchain, corrected 2026-11-16 (supersedes the Mac environment record below).** The Xcode
  license **is** accepted, `xcodebuild -showsdks` and `simctl` work, and iOS **27.2** simulator
  runtimes are installed. There is no iOS 26.5 runtime, so the local test destination resolves to a
  name only — CI stays pinned at Xcode 26.6 / iPhone 17 / iOS 26.5 and the divergence is recorded,
  not fixed. Two consequences: anything newer than the 26.5 SDK must be gated behind
  `#available` / `canImport` rather than assumed (local green proves nothing about the pinned SDK),
  and the host test suites **now run on this Mac** — `CairnChatDomain` 63 tests and
  `CairnProviderRemote` 35 tests, 0 failures — which the record below listed as impossible.

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

## Mac environment record — 2026-11-16 (first session on the M1)

Recorded because the entry above described the wrong machine, and because a local result must never
be read as a CI result. Everything in the table was produced by running the command and reading its
output on this machine; nothing here is inferred from a document.

| Check | Result |
|---|---|
| Model / arch | MacBook Pro 13-inch (M1, 2020), `arm64` |
| macOS | 27.2.1 (build 26B131) |
| Memory | 8 GB unified (8,589,934,592 bytes) |
| Free disk | ~24 GiB free on the data volume |
| Xcode | 27.2, build 27B52, `/Applications/Xcode.app` (Mac App Store install) |
| Swift — Xcode toolchain | 6.4.2 |
| Swift — Command Line Tools | 6.2.3, and **XCTest does not ship here** |
| SDKs installed | iPhoneOS 27.2, iPhoneSimulator 27.2 |
| iOS simulator runtimes | **none installed** |
| git / gh / XcodeGen | 2.56.1 / 2.104.0 (authenticated) / 2.46.0 |
| Repository | clean clone, `main` at `3352604`, HTTPS origin, no credential in the remote URL |

**Done:** `sudo xcode-select -s` — the active developer directory is now
`/Applications/Xcode.app/Contents/Developer`, and `xcodebuild -version` answers **Xcode 27.2, build
27B52**. **Still outstanding**, and this needs the user's password — a script must not accept a
license on someone's behalf:

```bash
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
xcodebuild -downloadPlatform iOS    # several GB against ~24 GiB free — check `df -h /` first
```

The block is total, and it was probed rather than assumed: `xcodebuild -showsdks`,
`xcodebuild -downloadPlatform iOS`, and `xcodebuild -license print` each refuse with the same license
error. `xcrun simctl` reports `unable to find utility "simctl"`, which is **misleading** — `simctl` is
present at `Contents/Developer/usr/bin/simctl`, so this is the license gate hiding a tool that is
installed, not a missing tool to chase. Until the license is accepted there can be no simulator
runtime download, no simulator build, no simulator test, and no host test run.

One Apple-API fact is **not verifiable from this machine**: the `-downloadPlatform` spelling, because
`xcodebuild -help` sits behind the same license gate. If that form is rejected, install a runtime from
Xcode → Settings → Components, or let the first build offer to download it.

**Local Mac verified across the three local commits (`3b4e756`, `69f7416`, `db11982`):**

- `Scripts/ci.sh guards` — **green, exit 0**: logging, ATS, hostname/address, signing, and the
  guards' self-test, now **41 ok, 0 failed** with the logging guard covered for the first time.
- `Scripts/ci.sh probe` and the simulator lane — **fail fast with the fix attached**, verified against
  this machine's real broken state instead of assumed: `probe` names the unaccepted license once
  instead of letting two SDK lookups repeat it, and `ci.sh test` refuses before `xcodebuild` can
  report a missing runtime as something else.
- `xcodegen generate` — **green**; the generated `App/Info.plist` carries `NSAllowsLocalNetworking`,
  and the ATS guard passes against that generated plist, not only against `project.yml`.
- `CairnChatDomain` and `CairnProviderRemote` library sources — **compile clean** on the host. The
  only diagnostic is the pre-existing unused `id` binding in `ChatStore.swift`.
- Those packages' **test targets — not run.** The Command Line Tools carry no XCTest and Xcode is
  unusable until the license is accepted, so `no such module 'XCTest'` is a toolchain gap here, not a
  code defect.
- Simulator build and simulator test — **not run**; there is no iOS simulator runtime on disk.

The four verification lanes, moved by this session or not:

- **CI-verified** — M2 holds at `3352604`: CI run
  [43797177054](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/43797177054) green, and the
  nightly Xcode 27 probe green on the same SHA at
  [43899619930](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/43899619930).
- **Local Mac verified** — guards and XcodeGen only, exactly as listed above. Nothing more.
- **Physical-device verified** — **pending.** The iPhone 15 Pro has never been attached to Xcode on
  this Mac; the checklist under *M2 device checklist* is what closes it.
- **Real-network verified** — **pending.** No LAN request and no WireGuard-tunnelled request has been
  made from this Mac.

M2 therefore stays **CI-verified only**.

## Parity program — P0–P5 (plan approved 2026-11-16)

Ledger: **`docs/PARITY.md`** (every owed feature, its spec section, milestone, status, and
verification label). Order is dependency-forced: guards → servers → on-device → the engine that
needs both.

| # | Scope | Spec | Status |
|---|---|---|---|
| P0 | Zero-paywall guard + self-test + CI wiring + this ledger + environment correction | brief §0 | **done** — CI-verified `44001146864` |
| P1 | Multi-server management, instant switching with per-server last model, `lmStudio` + `ollamaCloud` kinds, setup guide, user-initiated LAN scan | brief §3.4 | **done** — code landed and all five owed suites written (switching through `ChatSessionModel`, `LANDiscoveryService` on a fake transport, LM Studio + Ollama Cloud wire/codec, `ServerSelection` SwiftData round-trip, `ServersModel` selection + discovery); green on CI run `44015633614` (`de0ec5a`) |
| M3 | On-device inference (`mlx-swift-lm` + Foundation Models) + model manager with progress, cancel, unload, `/api/show` | §3.5 | **closed (code + CI)** — green run `44182366343` on `c03168f`, which carries `31162c7` + `38d5ed3` + `84cf613` + `7882498`; earlier runs `44171820190`, `44177831990`, `44179719494` also green; 65 `CairnTests` on `iPhone 15 Pro` locally. **On-device and real-network verification are still owed** — the checklist at the end of this milestone is the sign-off, and the MLX runtime has never been linked or run |
| P2 | Per-chat + default configuration with `configured` vs `unset`, capability-filtered payloads, injected context, themes | §3.2, §3.3, §3.10 | **done** — CI-verified `44144881214` on `823bd86`; local-Mac-verified 121 domain + 59 remote host tests, guards 53/53, 65 `CairnTests` on `iPhone 15 Pro`. Full record below; known gaps stay listed there |
| M4 | Hybrid Parallel + Synthesized engine | preserved core | **in progress** — engine, session path, and provenance storage landed 2026-11-17 (159 host tests green, guards 53/53, simulator build green); picker, progress panels, draft cards, and the real residency gate owed. Record at the end of this file |
| P3 | Tool runtime + built-ins + search routing (keyless default, SearXNG optional, cloud key-gated) | §3.7 | todo |
| M5 | Chat list, Markdown + code copy, Continue Generation, duplicate chat, temp banner, background processing, `.cairn`/`.md` | §3.1, §3.9 | todo |
| M6 | File + image attachments, chunked retrieval with citations, vision gating | §3.8 | todo |
| P4 | On-device model sharing server over LAN (`NWListener`, both dialects) | §3.6 | todo |
| P5 | Accessibility, AppIcon, licenses/privacy/issues, doc refresh | §3.10 | todo |

### P0 record — zero-paywall guard (2026-11-16)

Files: `Scripts/check-no-paywall.sh` (new), `Scripts/test-guards.sh` (+12 cases, 41 → **53**),
`Scripts/ci.sh` (`guards`), `.github/workflows/ci.yml` (guards job step),
`Packages/CairnProviderRemote/.../RemoteBodyDelegate.swift` (rename), `docs/PARITY.md` (new),
`ROADMAP.md`, `.clinerules`.

What the guard rejects in shipped sources and `project.yml`: a purchase framework or purchase API,
tier/upsell vocabulary, an artificial cap identifier, and a tracking hook. It prints `file:line`
only, never the matched text.

**Three bugs the self-test caught while P0 was being written** — this is why the self-test is worth
its keep, and each is a trap the next guard will fall into again:

1. `git ls-files | xargs -0 grep` — without `-z` the whole list becomes one bogus filename, so the
   guard **scanned nothing and reported success**. Command substitution also drops NUL bytes, so the
   `-z`/`-0` form fails the same way through a variable. Fixed with a plain file loop (`xargs -r` and
   `xargs -d` do not exist on macOS anyway), plus `-H` so a single matching file still reports
   `file:line`.
2. The guard **printed the word it bans** — in its banner, a rule label, and its remediation hint —
   which the self-test's "did not print the value" half rejected. All printed strings are now free of
   every forbidden term.
3. The guard caught **its own CI invocation line**, because the required filename contains the
   forbidden word and `.github/workflows/*.yml` was in scope. Workflows are now out of scope: a
   workflow cannot add monetization to the binary, and self-reference is not a rule worth keeping.
   `project.yml` stays in scope because that is where an app-facing build setting would land.

Also caught by running it: `RemoteBodyDelegate.swift` held a private `messageLimit = 240`, a
truncation bound on an error body, not a cap on the user. Renamed to `errorSnippetChars` rather than
exempted, per the rule that an ambiguous name is renamed and the guard is never widened. A CI comment
saying "subscription-free" was reworded for the same reason.

Verification: `Scripts/ci.sh guards` **exit 0** — all four privacy guards, the new guard, and the
self-test at **53 ok / 0 failed**. `Scripts/ci.sh build` → **BUILD SUCCEEDED**. Host suites
`swift test` → `CairnChatDomain` **63 tests, 0 failures**; `CairnProviderRemote` **35 tests,
0 failures**.

**CI-verified — run [44001146864](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/44001146864)
on `c4f58aa`, all three jobs green:** `Privacy guards` (five guards including the new one, plus the
53-case self-test), `Host unit tests (macOS)`, `Build + test on simulator`. P0 is therefore closed as
**CI-verified**; the local lane adds **local-Mac-verified** for the same work. Nothing in P0 is
on-device-verified or real-network-verified — no P0 change touches a network path, a device, or
memory.

Known gaps after P0: `check-no-paywall.sh` matches names and strings, not behaviour — a cap spelled
in some novel way still needs review, which is why the self-test exists. The M2 device checklist and
the real-network route remain open and unverified.

### P1 record — servers parity, closed on CI run 44015633614 (2026-11-16)

Implemented: `ServerBackend` is the single kind→endpoint/capability table (`ServerEndpoints` paths
are absolute and no kind declares a `v0` path, which `ServerKindBackendTests` enforces); selection
lives in `ServerSelection` keyed by profile UUID with `resolvedActive` falling forward past a
disabled or un-opted-in server; `ServerConnectionStatus.derive` is pure and order-bound so a
disabled row can never show a remembered success; `LANDiscoveryPlan` is pure (private-IPv4 only,
one /24, bounded in-flight probes, `emptyScanHint` names the Local Network permission only when
nothing at all was reached); the scan is user-initiated, cancellable, and yields drafts that go
through the ordinary validated save path.

Verification during the build-out was **local only**: 53 guard cases, 87 domain host tests (24 new),
35 remote host tests, and `xcodebuild build` for the simulator — an intermediate state, superseded by
the closure below. Ollama Cloud behaviour against the real service, and LM Studio's lifecycle
endpoints, remain unverified by design — the lifecycle calls are not wired (M3) and no network test
is run from this machine.

**Test suites landed (2026-11-16, this commit).** All five P1 suites required by
`docs/PARITY.md` §"acceptance" now exist, and the local lane is green on all of them:

| Suite | Layer | What it pins down |
| --- | --- | --- |
| `ChatSessionServerSwitchTests` (+ `ServerSwitchTestDoubles`) | domain | switching mid-conversation repoints the engine, restores that server's last model, and leaves the tree untouched; an unusable server is refused rather than half-applied |
| `LANDiscoveryServiceTests` (+ `LANDiscoveryTestDoubles`) | remote | one /24 swept once on a fake transport, one question per port then one generic retry, bounded parallelism (`peakConcurrency`), progress monotonic to the whole subnet, stop observed mid-sweep, and the honest empty-vs-unreachable hint |
| `LMStudioWireTests` / `OllamaCloudWireTests` (+ `WireTestSupport`) | remote | which endpoint each kind addresses, request encoding (usage asked for on the OpenAI surface; `think` never sent to the cloud), decoding (SSE vs NDJSON, a non-list is a typed failure, reasoning only from a field the server sent), and the cloud being inert with no packet until the opt-in |
| `ServerSelectionTests` | persistence (simulator) | active server + per-server last model read back from the row, each server keeps its own model, a deleted server leaves no trace, the read path prunes a pointer at nothing, repeated writes leave one choice |
| `ServersModelSelectionTests` / `ServersModelDiscoveryTests` | app UI (simulator) | one tap changes the shared choice and hands it to the workspace, a server that cannot answer is refused out loud with the notice that names the opt-in, deleting the active server repoints the chat; a scan never starts itself, two taps do not start two sweeps, stopping says nothing was saved, and a finding saves through the ordinary path with no token |

Local gate for that commit: `guards` 53/53, `CairnChatDomain` 95 tests, `CairnProviderRemote` 59
tests, `xcodebuild test` 45 tests — all 0 failures. **Local runtime note:** this Mac has no iOS 26.5
runtime, so `Scripts/ci.sh test` fell back to `iPhone 15 Pro` on the newest runtime it had (SDK
27.2), against CI's pinned `iPhone 17` / iOS 26.5 on Xcode 26.6. `Scripts/ci.sh probe` prints both
sides; a green CI run is what closes P1.

Two of my own test expectations were wrong and were corrected against the real behaviour rather than
the guess: SwiftData does not reject a second `@Attribute(.unique)` row on an in-memory store, so
that test now asserts the app-visible rule (repeated writes leave one choice, an older write does not
reappear); and a LAN kind's Add-server draft arrives prefilled with the scheme only (`http://`),
which is the intended rule — the user's address is never guessed.

**CI-verified — run [44015633614](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/44015633614)
on `de0ec5a`, all three jobs green:** `Privacy guards` (five guards plus the 53-case self-test),
`Host unit tests (macOS)` (95 `CairnChatDomain` + 59 `CairnProviderRemote`), and
`Build + test on simulator` (45 `CairnTests`). P1 is therefore closed as **CI-verified**; the local
lane adds **local-Mac-verified** for the same work. `@testable import CairnAppUI` in the app test
target compiled clean on the pinned Xcode 26.6, which is what let the scan lifecycle — deliberately
module-internal — be tested without widening it.

**Nothing in P1 is on-device-verified or real-network-verified**, and that is the honest edge of what
was built here rather than an oversight: Ollama Cloud was proven inert (no packet) before the opt-in
and proven to send exactly one request carrying the Keychain token after it — never against
`ollama.com` itself. LM Studio's endpoints were proven to be addressed and its lifecycle calls proven
refused without issuing a request — never against a running LM Studio. The LAN sweep was proven
bounded, one-question-per-port, monotonic in progress and cancellable mid-sweep on a fake transport —
never over a real /24. The Local Network permission denial is still a hint only, unproven on a device.

Known gaps carried forward: the M2 server device checklist and the real-network route stay open; the
guide sheet is build-verified with no automated UI test; and `check-no-paywall.sh` still matches names
and strings rather than behaviour, which is why its self-test exists.


### P2 record — per-chat configuration, injected context, and themes; closed on CI run 44144881214 (2026-11-17)

Implemented: `ChatConfig` is the one per-chat configuration (persona, `SamplingConfig` of optional
overrides, `ContextToggleSet`, response-format preference), and `configured` vs `unset` is a real
distinction — an unset knob is **absent from the request**, so the server's own setting stands.
`SamplingReference` is the single source for each knob's range, ladder and reference value
(context 2048…262 144 snapping ladder, max-tokens 256…32 768 behind a two-state Unlimited/Limited
choice, temperature 0.0…2.0 at 0.01 steps, top-P/min-P 0.0…1.0, top-K stepper 1…400, repeat penalty
0.0…3.0, repeat last-N 0…512). `SeedSetting` separates ownership: `.random(from:)` is Cairn's number
and randomize keeps the mode, `.fixed` is the user's typed number, cleared sends no key at all.
`ContextAssembly` writes the system message in a fixed order from the toggles, and the conditional
blocks (`toolGuidance`, `imageContext`) are written only when the turn really has tools or images —
a "use your tools" block on a turn with no tools teaches a model to claim an ability it was not given.
Preview and wire are the **same call** (`ChatSessionModel.injectedContextPreview` →
`ChatConfig.systemPrompt(in:turn:)`), which is what makes `testPreviewIsTheWireByteForByte` mean
something. Themes are `CairnThemeTokens` in two halves per palette with `ThemeProvider` resolving
appearance (a pinned appearance beats the device) and falling back to the shipped default for an id
this build does not know.

**Test suites landed (2026-11-17, `823bd86`).**

| Suite | Layer | What it pins down |
| --- | --- | --- |
| `SamplingReferenceTests` (15 cases) | domain | every knob's range and ladder, off-ladder snapping, `contextLabel`, the per-key explainers the `(i)` buttons render, and seed ownership |
| `ChatConfigSheetTests` (8 cases) | app UI (simulator) | preview equals wire byte for byte, everything off means **no system turn at all**, persona alone survives every toggle off, conditional blocks only when the feature is live, which keys a given server would drop, clear vs reset are distinct actions, seed control ownership, and the session preview is the config's own call |
| `ThemeAndAppearanceTests` (7 cases) | app UI (simulator) | 4 palettes each with two **different** halves, unique ids with a resolvable default, pin-vs-device appearance resolution, tokens picking the resolved half, swatch roles, and theme + appearance + default config coming back as one row after a relaunch; a saved default seeds a new chat and never rewrites an existing one |

**Local gate for the pushed commit (`local-Mac-verified`, macOS 27.2.1):** `CairnChatDomain` 121 tests
0 failures, `CairnProviderRemote` 59 tests 0 failures, `guards` 53 ok 0 failed, and `xcodebuild test`
**65 `CairnTests` 0 failures on `iPhone 15 Pro` / iOS 27.2** — `ThemeAndAppearanceTests` was run
isolated first (7/7) to prove the test host launches, then the whole bundle. Simulators shut down with
`xcrun simctl shutdown all` immediately after.

**A stalled test host, and the rule it taught.** A `test-without-building` run sat for 13 minutes with
**zero tests executed** and no `xctest` process at all: the app host never launched because the command
line asked for no build while the sources had moved since the last build. Killed by PID, result bundle
removed, and the isolated class was run with a real `test` action (which builds) — green in one pass.
The durable rule: **never `test-without-building` to find out whether the tree works** — build, then
test. `Scripts/ci.sh` now keeps the CI pin untouched (`iPhone 17` / iOS 26.5 on CI) and gives a local
Mac a destination it can actually resolve: `iPhone 15 Pro` on the newest installed runtime, created if
the machine never had one, with the simulator shut down after the run even on a red result — which is
what keeps an 8 GB Mac usable.

**CI-verified — run [44144881214](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/44144881214) on
`823bd86`, all three jobs green:** `Privacy guards` (five guards plus the 53-case self-test),
`Host unit tests (macOS)` (121 `CairnChatDomain` + 59 `CairnProviderRemote`), and
`Build + test on simulator` (**65 `CairnTests`** on `iPhone 17` / iOS 26.5). P2 is therefore closed as
**CI-verified**, with the same work also **local-Mac-verified** on `iPhone 15 Pro` / iOS 27.2. Nothing
in P2 is **on-device-verified** or **real-network-verified**.

Known gaps carried forward, stated plainly:

1. **Finding #21 is still unanswered.** The capability filter is proven in code and tests, but which
   sampling keys a *real* engine reads has never been observed: `Scripts/probe-remote-config.sh` is
   committed and has **not been run against a real server** — it needs a box the user runs, and no
   address for one may enter this repo. Finding #19 (defaults nested under
   `default_generation_config`, and Ollama's in `/api/show`) is in the same state.
2. **The sheet footer does not follow the theme.** `ChatConfigSheet.footer` and the preview card fill
   `Color(.secondarySystemBackground)` — a UIKit system token, not a `CairnThemeTokens` role — so a
   picked palette changes the chrome around them but not that surface. Per-view colour tokens beyond
   accent/canvas/appearance are still fixed.
3. **No character cap exists on the preview.** The handoff note named a 1200-character preview cap; it
   is not in this tree — `previewSection`, `ChatSessionModel+Config` and `ContextAssembly` hold no such
   bound, and the preview renders the whole message with its UTF-8 byte count. The real bound in the
   sheet is the persona editor's growth limit (`.lineLimit(3...8)`), so a long persona scrolls to eight
   visible lines. Recorded so the next session does not chase a cap that was never written.
4. **Deferred to P3:** the Generation Statistics toggle and the `Thinking` / `Tools` composer chips.
   Stats render; they cannot be turned off, and there is no elapsed time.
5. Numeric knobs are slider/stepper controls with a readout; only the seed is a typed field, so the
   ledger row that asked for typed numeric entry per knob stays `Partial` for that reason.

## M3 — On-Device Inference + Model Manager (in progress, started 2026-11-17)

Approved decisions for this milestone: link `mlx-swift-lm` for real in an isolated Swift 5 module
(pinned 3.32.3 = `mlx-swift` 0.32.3, since that release moved to a separate MLX release train);
curated static `mlx-community` catalog plus a validated free-text repo ID behind the
public-internet opt-in; LM Studio load/unload/download wired with tolerant decoding and marked
pending real-server verification.

**M3a landed — `Packages/CairnInferenceLocal` (27 sources, 52 host tests, guards 53/53).**

What is in it, and why it is shaped this way:

* `MemoryFitEstimator` sizes weights **plus** the attention cache for the *active* context
  (`2 × layers × kv_heads × head_dim × bytes_per_element × context_length`), saturating on overflow.
  Missing metadata yields a weights-only estimate that says so out loud
  (`precisionNotice`) instead of inventing an architecture. `May exceed available device memory` is
  the required notice for `tight` and `exceeds`.
* `os_proc_available_memory()` sits behind `MemoryReading`. It is an iOS-family call, so a macOS
  host returns `nil` = *unknown*; nothing may treat unknown as unlimited. A free Apple ID build has
  no increased-memory entitlement, so this reading is the real ceiling for the shipped app.
* `ResidentModelPolicy` is the single-resident rule as a pure function; `OnDeviceModelRegistry`
  executes it and releases everything on a memory-pressure signal
  (`SystemMemoryPressureSource`, spelled as a notification name so it is testable off-device).
* `FoundationModelsProvider` implements `InferenceProvider` with
  `canImport(FoundationModels)` + `#available(iOS 26.0, *)`, reading
  `SystemLanguageModel.default.availability` at the moment of use and surfacing the exact reason.
  It emits `.content` and `.metrics` only — the framework offers no thinking field, so no reasoning
  panel can appear for it. `streamResponse(to:)` returns a `ResponseStream<String>` of cumulative
  snapshots, so the provider emits deltas.
* `OnDeviceCatalog` is static (browsing must work offline); 8 curated `mlx-community` builds, sizes
  are published totals, badges only where published. `HuggingFaceRepoID` is the gate between a typed
  string and both a URL and a filesystem path; `ModelStoreLayout.slug` drops dots so no directory
  name can ever contain `..`.
* `ModelDownloadManager` checks the outbound opt-in **before** any request, streams progress, keeps
  resume blocks next to the model, requires a published SHA-256 to match, writes
  `cairn-install.json` last, and removes everything on uninstall.

Still open for M3, in order: `CairnInferenceNative` (Swift 5, `mlx-swift-lm`, actor boundary,
Metal gated off the simulator), the Model Manager UI (Running / Installed / Download),
Ollama `/api/ps` + `/api/show` and LM Studio load/unload lifecycle, and `project.yml` + app wiring
so the shipped target links the new package. Until that wiring lands, the app binary is unchanged.
Verification so far for M3a is **local green only** — no CI run number, no device, no real network.

## M3b — native runtime module, lifecycle, Model Manager, app wiring (**M3 code-complete 2026-11-17**)

| Commit | What landed | CI run |
|---|---|---|
| `31162c7` | Fix the host-job compile break M3a introduced: a local `matches` in `CatalogQuery` shadowed the static `CatalogQuery.matches` under Swift 6.2. Renamed to `matchedEntries`, callees qualified | `44171820190` |
| `38d5ed3` | `Packages/CairnInferenceNative` — the Swift 5 island + `DeviceTemplateChunkParser` (17 host tests) | `44177831990` |
| `84cf613` | `ModelLifecycleManaging` + Ollama/LM Studio lifecycle + 10 host tests (remote suite 59 → 69) | `44179719494` |
| `7882498` | Model Manager UI, pinned On-Device row, `project.yml` + `CairnApp` wiring | `44182366343` (green on `c03168f`, which carries all four commits — see the note) |

**Why the Swift 5 island exists.** `mlx-swift-lm` pulls C++ interop and swift-syntax macro plugins
that are not strict-concurrency clean, so a Swift 6 `complete`-mode target that imports it cannot
compile. Rather than relax strict concurrency anywhere else, the import is quarantined in one target
in Swift 5 mode and actor-wrapped at its boundary: `CairnChatDomain`, `CairnAppUI` and
`CairnInferenceLocal` never see an MLX type and all stay Swift 6 strict.

**The escape hatch, and what it costs.** `mlx-swift-lm` compiles swift-syntax macros and a vendored
C++ engine from source — a long wall-clock and memory cost on an 8 GB authoring Mac and inside a CI
time box. So the runtime links **only** with `CAIRN_MLX=1`; `CAIRN_SKIP_MLX=1` forces it out, and
that is what CI and the simulator build use. With it excluded the provider still conforms to
`InferenceProvider`, still reports `.onDevice`, and says in its own words that the runtime is not in
this build. **Unproven, stated plainly:** no build here has ever linked MLX, so the 3.32.3 call shapes
in `MLXNativeEngine.swift` are written from the package's published usage and not observed, and **no
MLX token has ever been generated anywhere**. Every one of those calls lives in that one file, so a
correction cannot move anything else. `CAIRN_MLX=1 Scripts/ci.sh native` is the command that settles
it, on a machine with the time and RAM for it.

**Lifecycle is a second boundary, not an edit to the first.** `RemoteModelManaging` is untouched — it
drains a pull and returns nothing, so the 59 tests that already depend on it keep their meaning.
`ModelLifecycleManaging` streams `ModelPullProgress`, holds a cancellation that closes the socket, and
adds `runningModels` / `detail` / `loadModel` / `unload`. The gates live in the declared backend table:
a generic OpenAI-compatible server is refused **before a request is built**, which
`testGenericOpenAIServerGetsCopyRatherThanLifecycle` proves by asserting zero recorded requests, and a
public-internet profile without the opt-in is refused the same way. Ollama reports a failed pull as
HTTP 200 with an in-band `{"error": …}` line, so the status code cannot be trusted alone and that line
is surfaced instead of being shown as progress.

**LM Studio is wired, not verified.** `lifecycleWired` flips to `true`, which means the calls are
really issued. It does not mean they work: the request envelopes for `/api/v1/models/load|unload|download`
have never been exercised against a running LM Studio from this machine. Decoding is tolerant, success
is claimed only when the server did not object, a refusal is shown in the server's own words, and
`LMStudioWireTests` still proves the old boundary refuses what this kind does not have. That row stays
open until a real LM Studio box answers.

**The UI keeps the module graph honest.** `CairnAppUI` still imports only `CairnChatDomain`. On-Device
availability crosses as an `OnDeviceEngineReport` value that `App/OnDeviceWiring.swift` builds from
`AppleModelAvailability` and `MLXNativeProvider.runtimeAvailability`, so no view can call a runtime and
the Servers row cannot claim a phone is ready when the build or the hardware disagrees. The first-run
copy that promised "Cairn does not run a model on this phone" is corrected, because as of this
milestone it is false. Both new packages moved to an iOS 18 floor to match `CairnChatDomain`, which
Xcode enforces across the whole dependency graph.

### Verification — the three categories, not merged

* **CI-verified:** `44171820190`, `44177831990`, `44179719494` green — guards 53/53, 121 domain +
  69 remote + 52 local + 17 native host tests, iOS build and `CairnTests` on the pinned simulator.
* **Local, on the UI/wiring commit `7882498`:** `xcodegen generate`, then
  `xcodebuild -scheme Cairn -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build` →
  **BUILD SUCCEEDED**; then `xcodebuild test` on the same destination → **65 test cases, 0 failures**;
  simulators shut down after. That commit's own run, `44181840064`, was **cancelled**, not failed:
  `ci.yml` sets `cancel-in-progress: true` and the documentation push superseded it. The closure run is
  **`44182366343`, green on `c03168f`** — the same source tree plus the docs — and that is the number
  M3 is claimed against.
* **On-device-verified: nothing.** Not one hardware-dependent claim in M3 has been observed on a
  phone — the Apple model's real availability, `os_proc_available_memory()`, a real memory warning, and
  MLX generation all need the device.
* **Real-network-verified: nothing.** Every lifecycle and download test in M3 runs against a stub
  transport or a loopback listener.

### Gaps carried forward, not hidden

1. The linked MLX build has never been compiled here, and no MLX output exists anywhere.
2. LM Studio's lifecycle payload shapes need a real server.
3. Ollama `/api/ps`, `/api/show`, `/api/pull` need a real Ollama box — the codecs were written from
   published shapes and round-tripped against recorded JSON only.
4. The Model Manager's Download tab pulls a model **to a server** (which is what §3.5 asks of it);
   installing weights **onto the phone** through `ModelDownloadManager` still has no screen driving it.
5. The two on-device engines are registered and selectable, but no turn has been run against the Apple
   model on hardware.
6. BG-task continuation and ActivityKit from the brief are untouched; neither was needed to close M3.

**M3 is closed on the code and CI axes — green run `44182366343`.** It is **not** closed on hardware or
on a real network: the on-device checklist below is the sign-off list, and until it is run on a phone
every hardware-dependent claim in this milestone stays unverified.



## M4 — Hybrid Parallel + Synthesized engine (**in progress**, started 2026-11-17)

**Landed: the hybrid engine, the session path that runs it, and the storage that keeps its
provenance. The picker, the progress panels, and the app-level residency gate are owed.**

### What landed, and what each piece decides

| Piece | The decision it owns |
|---|---|
| `HybridCandidate` / `HybridPlan` | A candidate is an **engine + model pair**, not an engine. A plan needs two distinct pairs; a half-chosen row is refused rather than sent. Stored as the optional `ChatConfig.hybrid`, so a chat written before M4 decodes with `hybrid == nil` and Cairn chooses from what is registered. |
| `HybridScheduling` | The memory rule as a pure function: remotes run together, one on-device side may join them, **two on-device sides never overlap** unless the injected gate reports measured headroom; sequential on-device runs get a release between them, and the on-device side runs last so it gets the whole budget. |
| `HybridResidencyGating` | The seam for the memory answer. `os_proc_available_memory()` lives in `CairnInferenceLocal`, above this module, so importing it here would close a cycle. Default `NeverTwoOnDeviceResident` — an unknown reading is not an unlimited one. |
| `HybridEngine` | One `AsyncThrowingStream<HybridEvent>` over the same `InferenceProvider.stream` every other turn uses: `withThrowingTaskGroup` for concurrent groups, a sequential loop with eviction between on-device groups, then the synthesizer. Candidate failures are **values**, never thrown away; only cancellation ends the turn early. |
| `HybridSynthesisPrompt` | The writer gets the question and the drafts and **nothing else** — no transcript. A side that failed or stopped is labelled as one even when it got part-way, so an unfinished answer cannot be unified as if it were finished. |
| `HybridTurnOutcome` | Decides once what the one node says and how it is credited: unified answer when the writer finished, otherwise the primary side's answer, otherwise the first side that answered. |
| `ChatSessionModel+Hybrid*` | Drains the turn into **one** assistant node, writing each side's partial text as it lands. `send`/`regenerate` route on `mode.isHybrid`; `cancelStreaming` reaches every side through the stream's `onTermination`. |
| `ChatRecord.provenanceJSON` | Provenance is one JSON column, not a column per field. `saveNode`'s update path now writes `providerID` too, so a synthesized node is credited to the engine that wrote its text instead of the first candidate. |

### Bugs the M4 tests found and fixed
1. A **failed side's partial text** was handed to the synthesizer with no label, so a truncated
   answer read as a finished one. `HybridSynthesisPrompt.content(of:)` now names the failure.
2. A **failed writer's truncated unified answer** was stored with state `.complete`. It is now
   `.interrupted` — its own unfinished words, honestly marked — and only a writer that produced
   nothing falls back to a side's answer (state `.complete`, credited to that side).

### Verification — 2026-11-17, local Mac (M1)
* **local-Mac-verified**: `swift test` in `CairnChatDomain` — **159 tests, 0 failures** (36 new
  hybrid tests: overlap measured through a ledger, the never-two-resident peak, eviction count,
  partial failure, all-sides-fail, cancellation, synthesis attribution/privacy/thinking-honesty,
  plan validation, pre-M4 `ChatConfig` decode, provenance and draft round-trips, one-node session
  behaviour, regenerate-as-sibling). `bash Scripts/ci.sh hosts` green across all four suites.
* **local-Mac-verified**: `bash Scripts/ci.sh guards` — 53/53; `xcodegen generate` +
  `Scripts/ci.sh build` — ** BUILD SUCCEEDED ** on the simulator.
* **CI-verified**: not yet — this slice is being pushed for a run to cite.
* **on-device-verified / real-network-verified**: owed. The residency rule is only proven against
  a fake gate until the real `os_proc_available_memory()` gate is wired and run on a phone.

### Owed before M4 can be claimed
1. `HybridConfigSection` (two engine+model rows, the synthesizer picker, the refusal text),
   `HybridProgressView` (live per-side phase, chars, tok/s), `MessageRow+Hybrid` (collapsible
   draft cards + the one-line provenance), and the menu rows that let a chat enter a hybrid mode.
2. `HybridWiring` in `App/` — the real residency gate built from `OnDeviceModelRegistry` +
   `os_proc_available_memory()`, injected into every session; `evictResidentModel` must actually
   unload, not just answer no.
3. `CairnTests` hybrid cases on a simulator, then `docs/PARITY.md` §0d + §3.11.
4. A green CI run number on the commit that lands this — no milestone is claimed without one.

### Process note — why CI run `44193388503` went red and `25ddcb9`'s guard looked green locally
`Scripts/ci.sh guards` runs the guard self-test, which plants values in a throwaway tree and then
checks **the committed tree**. Files that are still untracked are therefore never scanned locally,
so a new file carrying a forbidden word passes on the Mac and fails on CI. The word here was the
tracking-hook list's `telemetry`, in a doc comment that meant "this is not tracking" — exactly the
kind of comment the rule forbids inside shipped scope. Fix: reword the comment (never exempt it).
Before pushing, run the guard against the **working tree**: `bash Scripts/check-no-paywall.sh`.

CI run `44193788309` then went red on a different axis: `testStoppingTheTurnEndsTheStreamWithoutClaimingSuccess`
slept 120 ms and then cancelled, so on a loaded runner no fragment had landed yet and the
"partial answers reached the node" assertion failed. The rule it taught: **never sleep to reach a
state — wait for the state.** The drain now raises a `PartialAnswerFlag` the moment a side says
something, the test stops the turn only after that flag is raised, and the drain calls
`Task.checkCancellation()` between events exactly as the session drain does. Re-ran that suite 5×
and the session-level hybrid suite 3× locally before pushing.