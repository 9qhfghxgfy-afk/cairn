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
| 5 | Advanced controls, interruption recovery, export/import | **closed** — code + every suite green on `0ecd1d4`; the 14-line device checklist and three named gaps stay open (see `## M5`) | [44396176219](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/44396176219) |
| 6 | Local RAG, vision, web search, voice | todo | |
| 7 | Parity backlog | todo (per-item approval) | |
| P0 | Zero-paywall guard + parity ledger | **done** — all gates green on `c4f58aa` | [44001146864](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/44001146864) |
| P1 | Servers parity: active-server selection, one-tap switching with per-server last model, `lmStudio`/`ollamaCloud` kinds, guide sheet, user-initiated LAN scan | **done** — code + all five required suites green on `de0ec5a` | [44015633614](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/44015633614) |
| P2 | Per-chat + default configuration, `configured` vs `unset`, capability-filtered payloads, injected context, themes | **done** — code + both new simulator suites and the domain suite green on `823bd86` | [44144881214](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/44144881214) |
| P3 | Tool runtime + five built-ins + search routing (keyless / own SearXNG / Ollama Cloud key-gated) + `Thinking`/`Tools` chips + Statistics toggle | **done** — code + every tool suite green on `0b3e3fc` | [44242238211](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/44242238211) |
| P3b | Task B — Web search providers: DuckDuckGo default, own SearXNG, Ollama Cloud; consent asked before the socket; the Web Search settings screen | **closed (code + CI)** — guards 53/53, host suites 492 domain + 170 remote + 60 on-device + 17 native, simulator build **SUCCEEDED** and 171 `CairnTests` green on `f7a4f77`; **not** on-device-verified, **not** real-network-verified — the 16-line Task B device checklist stays open (see `## Task B`) | [44567976658](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/44567976658) |
| P4 | LAN model sharing: `NWListener` surface answering Ollama's `/api/*` and OpenAI's `/v1/*`, per-session opt-in, generated key in its own Keychain service, foreground-only | **closed (code + CI)** — guards, all four host suites, simulator build and 147 `CairnTests` green on `b523ca9`; **not** on-device-verified, **not** real-network-verified | [44466484720](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/44466484720) |
| P5 | Accessibility pass, AppIcon pipeline, licenses + privacy statement + issues link, doc refresh | todo | |
| P6 | Built-in `get_location`: one position read from CoreLocation, consent settled **before** any radio work, no geocoding, per-chat switch, no outbound badge | **done — CI-verified** on `a02eb51`: Privacy guards green with the guard self-test at 53/53, Host unit tests on macOS (535 domain + 170 remote, 0 failures), Build + test on iPhone 17 / iOS 26.5 (build green, **190 `CairnTests`, 0 failures** — 14 of them this seam: 9 wiring, 5 mapping). On the Windows authoring machine: 535 domain tests green, guards 53/53, 593 files parse clean — which is the whole of what this machine can say, since CoreLocation, SwiftUI and XCTest-on-macOS do not build here. **Not `on-device-verified`**: every refusal test answers a counting fake, no iPhone has raised iOS's own permission prompt, and no real `CLLocationManager` has produced a fix in any test. **`real-network-verified` cannot apply** — there is no socket: `NetworkClass.onDevice`, no badge, no opt-in, no geocoder | [44634743108](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/44634743108) |

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
| M4 | Hybrid Parallel + Synthesized engine | preserved core | **Closed** — engine, session path, provenance storage, hybrid picker, live panels, draft cards, and the measured residency gate. **CI-verified `44209524177`** on `9bbd82b` (guards 53/53; 159 domain + 69 remote + 60 on-device host tests; simulator build + 95 `CairnTests`, 0 failures). **Not** on-device-verified, **not** real-network-verified. Record at the end of this file |
| P3 | Tool runtime + built-ins + search routing (keyless default, SearXNG optional, cloud key-gated) | §3.7 | **Closed** — the loop (native wire **and** prompt-protocol fallback), the five built-ins, the three search routes with the F4 resolution, per-chat arming with the outbound badge and disclosure, the tool run on the one assistant node with its cards, and the deferred Statistics toggle. **CI-verified `44242238211`** on `0b3e3fc` (guards 53/53; host suites 184 domain + 93 remote + 60 on-device + 17 native, 0 failures; simulator build **SUCCEEDED** + 104 `CairnTests`, 0 failures on iPhone 17 / iOS 26.5). **Not** on-device-verified, **not** real-network-verified. Record at the end of this file |
| M5 | Chat list, Markdown + code copy, Continue Generation, duplicate chat, temp banner, background processing, `.cairn`/`.md` | §3.1, §3.9 | **Closed** — the domain half and the screen half are both written: chat list with search, rename, duplicate, delete and open; Markdown answers with highlighted code and copy-as-prose / copy-the-source; Continue on a stopped, interrupted or token-cut answer; the temporary-chat line with keep-a-copy; `.md` and `.cairn` export through the system share sheet; `.cairn` import from the file picker and by opening a file from another app; a backgrounded turn really is stopped and offered for continuation. 268 domain host tests green, guards 53/53 local. **CI-verified `44396176219`** on `0ecd1d4` (guards 53/53; host suites 268 domain + 93 remote + 60 on-device + 17 native, 0 failures; simulator build **SUCCEEDED** + 108 `CairnTests`, 0 failures on iPhone 17 / iOS 26.5). **Not** on-device-verified, **not** real-network-verified: the 14-line M5 device checklist has never been run on a phone, and three named gaps stay open — `BGContinuedProcessingTask` for a turn that outlives the app, an all-chats export, and an editable title in the top bar. Record at the end of this file |
| M6 | File + image attachments, chunked retrieval with citations, vision gating | §3.8 | **code complete, CI-verified 2026-11-18 — run `44429557557`; device pass owed.** Domain engine (accept ceilings, image prep rule, text extraction, chunking, BM25 retrieval, grounding, vision gate), persistence (attachment and citation columns, file store beside the database, delete cleanup), and the UI/app half: composer with Photo Library and Files, staged chips with remove, the refusal / vision / storage lines, chips and sources on the message row, metadata-only export, the app's ImageIO preparer, and the wiring that hands every session the store's reader. 328 domain host tests, 29 new simulator tests, guards 53/53. **Not on-device-verified, not real-network-verified.** Record at the end of this file |
| P4 | On-device model sharing server over LAN (`NWListener`, both dialects) | §3.6 | **Closed** — the domain half, the `NWListener` half, and the screen half, all compiled and tested. **CI-verified `44466484720`** on `b523ca9` (guards 53/53; host suites **423** domain + **112** remote + **60** on-device + **17** native, 0 failures; simulator build **SUCCEEDED** + **147** `CairnTests`, 0 failures on iPhone 17 / iOS 26.5). The loopback exit condition is met for real: five checks drive a live `NWListener` over `127.0.0.1` and get a keyed model list in both dialects with 401 without the key, a streamed Ollama answer arriving as NDJSON and ending with `"done":true`, a 404 for a name nobody ticked, and a refused port after `stop()`. **Not** on-device-verified, **not** real-network-verified: no phone has ever bound a port, no real client (Ollama CLI, an OpenAI SDK, a real app on a laptop) has ever talked to it, the Local Network prompt has never been seen, and whether iOS pins the listener to one address or hands back the device-wide scope is unknown outside a phone. Record at the end of this file |
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
   Stats render; they cannot be turned off, and there is no elapsed time. *(Both landed in P3 — the
   elapsed readout, the toggle, and both chips are green on `44242238211`; see the P3 record.)*
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



## M4 — Hybrid Parallel + Synthesized engine (**closed 2026-11-18**, started 2026-11-17)

**Landed: the hybrid engine, the session path that runs it, the storage that keeps its provenance,
the picker and panels that make a hybrid turn legible, and the residency gate that answers the memory
question by measuring instead of assuming. What is owed now is a phone and a real server, not code.**

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
| `TwoResidentBudget` (M4b) | The two-resident answer as a pure function in the module that owns the reading: both sides may be resident only when two footprints fit inside the usable four-fifths of a **positive** reading. Unknown, zero, tight and overflowing readings all say no; overflow saturates to no rather than wrapping into yes. |
| `OnDeviceResidencyGate` (M4b) | The seam answered for real. Headroom is re-read on every question, so a cached "yes" cannot outlive the budget that justified it, and a release goes through `OnDeviceModelRegistry.releaseAll`, which calls the runtime unloader per model rather than only clearing bookkeeping. |
| `App/HybridWiring.swift` (M4b) | Where the real gate is built and handed down, reading from the same registry the memory-pressure watch already uses — one owner for what is resident. `CairnChatDomain` cannot import `CairnInferenceLocal`, so this is the only place the two meet, and `project.yml` compiles it into the test bundle so the factory is proven rather than trusted. |
| `HybridPlanSlots` (M4b) | What a tap does to a plan, as pure functions: two rows always exist, choosing an engine re-resolves its model because a name belongs to one engine only, and the writer may only be a side that is really in the plan. The sheet and its tests read one rule. |
| `HybridConfigSection` (M4b) | The two engine+model rows, the writer picker, and the refusal text, mounted through a new `extra` slot on `ChatConfigEditor` so the Default Configuration editor — which has no engines in front of it — does not have to know hybrid exists. |
| `HybridProgressView` + `HybridPanelRule` (M4b) | One row per candidate in plan order: phase, characters landed, and that side's own measured tok/s — counts, never text. The panel shows only for a hybrid mode with a turn in flight, so a finished turn cannot keep animating in a chat that moved on. |
| `HybridDraftCard` + `MessageRow+Hybrid` (M4b) | The drafts are read off the one node that owns them, each collapsible, each with its own numbers and its own typed failure. A side's reasoning panel appears only when that side's `thinking` field is non-empty: no panel is written around an answer with no reasoning, and none borrows the other side's. |
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
* **CI-verified** (engine slice): green run **`44195224728`** on `4689d42` — privacy guards, host unit
  tests (159 domain tests, four host suites), and build + test on the simulator all passed.
* **CI-verified** (M4b, the closure): green run **`44209524177`** on `9bbd82b` — guards 53/53; host
  suites **159 domain + 69 remote + 60 on-device** (Swift Testing), 0 failures; simulator build plus
  `CairnTests.xctest` **95 tests, 0 failures** on iPhone 17 / iOS 26.5. What that run proves and the
  host suites cannot: the hybrid views compile into the app, `App/HybridWiring.swift` links into the
  test bundle and its gate agrees with `TwoResidentBudget` on whatever the platform reports, the gate
  a workspace is handed is the gate the assembled turn runs with (asserted by identity), and a hybrid
  node round-trips through a real SwiftData runtime while a pre-M4 row still opens.
* **on-device-verified**: **owed**. No phone has run this. A host build has no
  `os_proc_available_memory()`, so the gate reads `nil` and answers no — the honest answer, but not a
  measurement from the device the feature exists for. The first real "yes" is still ahead of us.
* **real-network-verified**: **owed**. Every hybrid turn in CI speaks to mocks. A phone against a real
  Ollama or LM Studio server — with one side failing mid-stream and a release between two on-device
  sides — has never been observed.
* The red runs on this milestone are recorded below, because each one taught a rule worth keeping.

### Rules the two M4b red runs taught — each is a rule, not a taste
* CI run **`44207149883`** — `ChatConfigEditor+Persona.swift:39:16: static stored properties not
  supported in generic types`. Mounting the hybrid section through `extra` made `ChatConfigEditor`
  generic over that section, and a generic type has no single storage for a static property — there is
  one type per `Extra`. The wording became a computed static property, which reads the same at the
  call site. The rule: **before making a type generic, search its extensions for `static let`**; the
  error surfaces in a file nowhere near the change that caused it.
* CI run **`44208121121`** — two rules the test bundle would not bend around. `await` cannot sit inside
  an `XCTAssert` autoclosure, so an actor's answer is taken into a name first (which also reads
  better: it was held, then it was not). And `NSLock.lock()` is unavailable from an asynchronous
  context, so a counter kept by a `@MainActor async` method needs no lock — say in the comment what
  serialises it instead of keeping a lock that can never be taken.

### Closed — and what M4 still owes after closing
1. **A phone.** Whether a hybrid turn with two on-device candidates is ever admitted on measured
   headroom, and whether the release between sequential sides actually lowers the footprint. Both are
   device measurements; neither can be answered from this machine or from CI.
2. **A real server.** One hybrid turn against Ollama and one against LM Studio on the LAN, with one
   side stopped or failed, and the provenance line read back after a relaunch.
3. **Unload depth.** `OnDeviceModelRegistry.releaseAll` is only as strong as the unloader a runtime
   registers with it. Apple's system-managed model has no per-model unload and MLX does not yet expose
   one, so a "release" today is bookkeeping plus whatever the runtime genuinely gives up — stated here
   so no later reader mistakes it for a measured unload.

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

## P3 — Tool runtime, built-ins, and search routing (**closed 2026-11-18**, started 2026-11-17)

Two commits carried the code (`e84528c` — domain loop, registry, prompt protocol, routing, calculator,
persistence; `74f1774` — the wire, the web tools, the UI, and the tests that prove them) and the runs
below carried the fixes. The plan is §3.7 plus the `docs/PARITY.md` ledger; this is the record of what
shipped and how far the checks actually reached.

### What landed

| Piece | The rule it holds |
|---|---|
| `ToolRegistry` / `ToolExecuting` / `ToolExecutionContext` | One name→tool map, and one value saying what a turn may do. The chat's `Tools` chip and the outbound acknowledgement are **separate** switches, so a tool that leaves the device is refused even when the chip is up — the check lives in the context, so no handler has to remember it. |
| `ToolLoop` / `ToolLoopEngine` / `ToolLoopPolicy` | A step is one model call. Calls run, their text is fed back, the model answers; the bound is a sanitised policy value (`mayRunAnotherStep(stepsTaken:)`), cancellation is honoured between steps, and the turn ends with a stated `stoppedAtStepLimit` rather than the UI inferring it from a count. |
| `ToolRun` / `ToolInvocation` on the node | A call belongs to the answer it fed, so the run lives on the **one** assistant node: it replays, branches, exports and imports with that answer, and a call can never be branched away from the turn it justified. A turn with no tools writes **no** blob at all, so a pre-P3 row reads "no tools ran", not "zero tools ran, somehow". |
| `ToolRouting` + `PromptToolProtocol*` + `Remote/ToolWireSchema` | Two ways to reach a tool, never conflated: a backend with documented function calling gets schemas on the wire (both dialects), one without gets an instruction block and Cairn parses its prose under a bound. Which one ran is recorded on the node and printed on the card — parsed is never drawn as native. |
| `CalculatorEvaluator*` + `CalculatorTool` + `CalculatorError` | Cairn's own hand-written, bounded parser. Nothing evaluates a string: no `NSExpression`, no format string off an untrusted input, no `value(forKey:)`, no symbol lookup by name. A hostile expression is a typed error the model can read. |
| `MailDraft` + `ComposeMailTool` + `MailComposerPresentation` | The whole mail story, deliberately small: Apple's own composer opens with the draft filled in and **nothing in Cairn can send it**, so the tool says the draft was *offered for review* and the tool description tells the model never to state a send. A device or build with no composer gets no `compose_mail` rather than a tool that claims success and opens nothing. |
| `WebSearchRouting` / `WebToolSettings` + `CairnProviderRemote/Tools/*` | The F4 resolution: the user's own SearXNG address wins when set — plain `http://` is allowed for it because that server is on their own network — otherwise the keyless public endpoint, and Ollama's own search only when the active profile is `ollamaCloud` **and** its Keychain key is present. A request is *built* before it is sent, which is the only way "only the query left" can be asserted rather than hoped. |
| `ToolChipRule` + `ToolToggleSet` + `ComposerChips` + `ToolSwitchMenu` + `ToolsOutboundBadge` + `MessageRow+ToolCards` + `SettingsView+Tools` | Tools ship off. Arming is per chat, and **one tap arms it** — `ToolChipRule` decides up-or-down only, so neither a backend's advertised capability nor an unanswered acknowledgement can gate the chip (the device round of 2026-11-19 took the veto out; see `## Device bug round`). The acknowledgement is still asked, beside the arming rather than in front of it, with **both** ways out: `.armed` (web included once acknowledged) or `.localOnly` (arithmetic and mail drafts only) — a real state, not a refusal, in a per-tool menu whose web switches stay dimmed until the acknowledgement is up. The outbound badge is read back off stored nodes, so it survives the turn, the scroll, and a relaunch. |
| `App/ToolWiring.swift` | The only place a registry can be assembled: a window, a Keychain and two Settings switches meet here and the domain reaches for none of them. `project.yml` compiles it into the test bundle so the factory is proven, not trusted; the registry is re-assembled when either switch moves, so arming a chat right after saying "yes" really works. |
| `ChatConfig+Decoding` + `Mapping` + `Records` | The upgrade is additive in both directions: a pre-P3 configuration blob decodes with the chip **down** (an upgrade may not arm a chat the user never opted into), a pre-P3 node row has neither tool column, and a pre-P3 settings row keeps both shipped defaults — internet unacknowledged, statistics still shown. |

### Verification — 2026-11-18

* **CI-verified** (the closure): green run **`44242238211`** on `0b3e3fc`.
  * **Privacy guards** — all five guards plus the guard self-test: **53 ok, 0 failed**.
  * **Host suites, 0 failures** — **184** domain tests (XCTest), **93** remote tests (XCTest),
    **60** on-device inference / memory / catalog tests (Swift Testing, 14 suites), **17**
    native-runtime isolation + template-marker tests (Swift Testing, 2 suites, MLX runtime excluded
    on purpose).
  * **Simulator lane** — **BUILD SUCCEEDED** for the app against the iOS 26.5 SDK, then
    `CairnTests.xctest` **104 tests, 0 failures** on iPhone 17 / iOS 26.5. Nine of those are new
    since M4's 95: `ToolRunPersistenceTests` (3), `ToolLegacyRowTests` (3), `ToolWiringTests` (3).
* **What only the simulator lane can prove** — and the host suites cannot, because `swift test` never
  builds `CairnAppUI`, `App/`, or the test bundle at all. This is the lane where `MessageUI` is really
  imported, where `App/ToolWiring.swift` is linked into the test bundle so the registry factory can run
  against real stores instead of a double, where a `ToolRun` round-trips through a live SwiftData
  runtime, and where a pre-P3 node row, a pre-P3 configuration blob and a pre-P3 settings row are read
  back by the current reader. The wiring assertions are the ones that close the loop: the registry a
  chat is handed is the registry the two switches describe — for the session that is live and for a chat
  opened later — and a LAN server's own bearer token never becomes a search key.
* **local-Mac-verified: nothing for this closure.** The closing change was made on the Windows fallback
  machine, which has no Swift toolchain, so no build and no test was run locally. What was verified
  here: `bash Scripts/ci.sh guards` — **53/53**, and `bash Scripts/check-no-paywall.sh` against the
  working tree — clean. The build and the tests are CI's for this commit, and that split is stated
  rather than blurred.
* **on-device-verified: owed.** No phone has run any of it. `MFMailComposeViewController.canSendMail()`
  has never been read on a device, the composer has never opened, the iPad popover anchoring has never
  been exercised, no human has tapped the first-use disclosure, and the Local Network prompt that a
  self-hosted SearXNG on the LAN will raise has never been seen — and a denial there genuinely breaks
  the connection.
* **real-network-verified: owed.** Every web-tool assertion runs against `RecordingWebTransport` or a
  stub, so "only the query leaves" is proven about a *request that was built*, not about a socket. No
  real keyless endpoint, no real SearXNG instance, and no real `POST /api/web_search` with a real
  Ollama Cloud key has been exercised, and the redirect-onto-a-private-address refusal is a coded rule
  rather than an observed hop.


### Rules the P3 red runs taught — each is a rule, not a taste

* CI run **`44235943573`** — the new domain suites did not compile: two switches over a newly added enum
  case were not exhaustive, a recorded chunk list was captured as a `var` inside a `@Sendable` closure, and
  an array literal was written where a `.content(...)` case was meant. The rule: **a milestone that adds a
  case to an enum audits every switch over it in the same commit**, and a test double that accumulates
  stream chunks is a value the compiler can check, not a mutable capture.
* CI run **`44238447777`** — three assertions failed against the shipped code rather than against the
  intent, and one of them was instructive. `http://192.168.1.20:8080/v1/models` came back `.notHTTPS`
  where the test demanded `.privateTarget`. The guard was right and the test was wrong: that address is
  both private **and** plaintext, and the tool's https rule is the plainer reason, consulted first. Cairn
  *does* reach a private server over plain `http` — through `ServerProfile`, which is not this tool — and
  the corrected test now says so in its comment. The rules from this run: **assert the reason the code
  really reports, in the order it checks**; **a fragment-rejoin assertion is only worth what its fixture
  is** — write the fragments the wire really sends, then read the rejoined value off the code; and **never
  index a decoded list before its count has been asserted**, which is what turned a zero-result fixture
  into a fatal index trap in front of a real assertion.
* CI runs **`44239112595`** and **`44239762797`** — the Wikipedia excerpt assertions were written against
  prose with collapsed spacing. What the extractor returns is **one trimmed line**: no markup, no newline
  however the markup broke, the em dash Wikipedia wrote, and an ampersand kept rather than rewritten. The
  rule: **read the reader before writing the assertion.** CI's own failure text is the cheapest source of
  truth available, and it is the one that finally settled the fixture.
* CI run **`44239762797`** — the last red, closed by `0b3e3fc`:
  `conformance of 'MailComposerPresentation' to protocol 'MFMailComposeViewControllerDelegate' crosses
  into main actor-isolated code and can cause data races`. Two rules came out of it. **A `@MainActor` type
  conforming to a delegate protocol the SDK has not annotated carries `@preconcurrency` on the
  conformance** — that is the compiler's own suggestion at the conformance site, and it records that Apple
  delivers the callback on the main thread instead of pretending the protocol is callable from anywhere.
  And **an iOS-only file is uncompiled, not tested, until the app lane builds it**: this file sits behind
  `#if canImport(UIKit) && canImport(MessageUI)`, a macOS host build has no MessageUI, so four host
  suites stayed green for six pushes while the app itself could not build. **A green `swift test` on the
  Mac says nothing about the app target.**

### Closed — and what P3 still owes after closing

1. **A phone.** Whether `canSendMail()` is ever true on a device with an account configured; whether the
   composer really appears above the sheet the chat left open (that is why the top-most controller is
   walked, and it has never been watched); whether the disclosure's two arms read as two real choices;
   whether the badge is still on screen after a relaunch; and whether the Local Network prompt a
   self-hosted SearXNG raises is accepted — a denial there genuinely breaks the connection.
2. **A real endpoint, one per search route.** The keyless redirector's HTML is the most fragile thing in
   the milestone: it is parsed off a public page Cairn does not control, CI pins it with a fixture, and the
   day that page changes the tool degrades to "no results" instead of failing loudly. A self-hosted
   SearXNG on the LAN and Ollama's keyed `POST /api/web_search` have never been reached either.
3. **A real model's prose for the prompt protocol.** The parser is tested against fixtures that were typed
   to look like model output; no model has yet emitted the block for it, and `ToolRouting` has never had
   to choose between native and prompt against a real backend's advertised capability.
4. **`forceWebFetch` was dead; it is not any more.** It was written `false` on every path, so the key stayed
   reserved while the web tools were live. The device round of 2026-11-19 made it follow the switch **and** the
   tools actually offered on the turn (`ContextAssembly.webFetchIsLive`) and carried it on every continuation
   step (`ToolLoop`). CI `44599188881` — `WebFetchLivenessTests`, `ToolLoopStepRequestTests`. Whether a real
   model obeys the block it unlocks is still owed to a device pass.
5. **One warning that predates P3 and is not folded into this diff:**
   `Tests/CairnTests/ServerSelectionTests.swift:120` discards the result of
   `createConversation(title:mode:config:isTemporary:)`, which CI surfaces as an annotation. It is a
   P1-era test-hygiene nit in a file this milestone does not own; named here so it is not mistaken for a
   P3 regression, and left for whoever touches that suite next.

## M5 — chat list, Markdown, export/import, Continue, temporary chats (**closed 2026-11-18**, CI-verified; started 2026-11-18)

The screens the domain was built for. Nothing here is a new capability in the store: a chat is still a tree,
an edit is still a sibling, and a temporary chat still never reaches disk. What landed is the ability to see
the list, read an answer as the Markdown the model wrote, move a chat across the edge of the device, and ask
for the rest of a stopped answer.

### What landed, and what each piece decides

- **`ChatListView` + `ChatRowView`** — the drawer behind a leading toolbar slot. Rows come from the workspace
  in the domain's order, filtered on title; the open chat is marked rather than absent; swiping a row gives
  Delete, Duplicate, Rename; a file leaves through the share sheet and arrives through the file picker.
  Acting goes through the workspace by id, never through the array on screen, which is a snapshot.
- **`ChatListQuery`** (domain) — ordering and title filtering as pure functions, so what the list shows is
  testable without a view, and a hidden chat cannot be invented by the view either.
- **`MarkdownMessageView` / `MarkdownBlockView` / `MarkdownInlineText`** — a finished answer renders as the
  Markdown the model wrote; a streaming answer stays plain text, because a fence typed half a sentence ago
  draws a block that has not closed, and a bold marker mid-word is a `**` the model has not finished. Links
  are tappable and say they leave the app.
- **`CodeBlockView` + `CodeSpanStyle`** — colour from the domain's span table, wrapping instead of a hidden
  horizontal scroller, and "Copy code" handing back the block's own lines rather than what is painted.


- **`MessageRow+Controls`** — Stop stays while streaming; after a turn that was stopped, interrupted or cut
  at the token limit, the row offers **Continue** — add the rest of this answer, on a branch of its own —
  plus **Copy text** and
  **Copy Markdown**. The three continuation cases are one domain rule (`ChatContinuation`), so the button
  cannot disagree with the state.
- **`TempChatBanner`** — a persistent line in the chat plus the badge already on the toggle: the chat is not
  in the list, it is not written when the app closes, and "Keep a copy" writes a saved chat while leaving the
  temporary one open.
- **Export and import** — `.md` for reading, `.cairn` for restoring, both handed to the system share sheet
  through a transient `fileURLWithContents`; nothing is cached on disk by the app. Import accepts either
  shape, refuses what it does not recognise, and re-assigns fresh ids on a clash instead of writing over a
  chat that is already here.
- **`ChatFileNames`** — a name from the title, `Untitled-chat-2026-11-18T14-32-05Z` otherwise (second-precise
  and colon-free, so two untitled chats exported on the same afternoon are two files), and anything that is
  not a letter or a digit becomes a dash, so a title containing a slash cannot become a folder.
- **Backgrounding ends a turn** — `CairnRootView` interrupts an active turn when the scene leaves the
  foreground, which is what makes the paused marker and the Continue offer true rather than decorative.

### Verification, by tier — the tiers do not substitute for each other

- **local-Windows-Swift-verified** (Swift 6.4.2 on Windows — a *newer* compiler than CI's Xcode Swift, which is
  how the two `CairnChatDomain` errors in `MarkdownFence.swift` and `ChatImport.swift` were caught here and not
  on CI): `swift test --package-path Packages/CairnChatDomain` → **268 tests, 0 failures** (ordering, title
  filtering, safe file names, duplication, continuation, Markdown, highlighting, export/import round-trips).
  `bash Scripts/parse-check.sh` → **330 files parse clean**: a `swiftc -parse` pass over every app, package and
  test source, the only local check that sees `CairnAppUI`, `App` and `Tests/CairnTests` at all, and syntax
  only. It earns its place — the first M5 push left an unbalanced `struct` in `MessageRow` and a
  `guard case … , let …` the parser rejects, and both were visible locally the moment it existed. The other
  three host suites are **not** checked here: `CairnProviderRemote` and `CairnInferenceLocal` need Apple-only
  frameworks and `CairnInferenceNative` runs under `CAIRN_SKIP_MLX=1`, so they are CI's to run.
- **local-guards-verified:** `bash Scripts/ci.sh guards` → **53 ok, 0 failed** (logging, ATS, hostname and
  private-address, signing, zero-paywall, and the guards' own self-test), and `Scripts/check-no-paywall.sh`
  clean on the same tree.
- **CI-verified:** green run [44396176219](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/44396176219) on
  `0ecd1d4` — `Privacy guards`, `Host unit tests (macOS)` and `Build + test on simulator` all pass. Counts read
  off that run's own log: **268** `CairnChatDomain` + **93** `CairnProviderRemote` + **60**
  `CairnInferenceLocal` + **17** `CairnInferenceNative` (runtime excluded, as always) on the host, and **108**
  `CairnTests` on iPhone 17 / iOS 26.5 — **0 failures in every suite**, and not one failure line anywhere in
  either job's log. `CairnAppUI`, the app target and `CairnTests` are compiled only by CI; this machine has no
  Xcode, so nothing about them is verified any other way. Four runs came before that one and each is worth its
  record: `44374999843` (the two parse errors `parse-check.sh` was written to catch), `44377313988` (`private`
  members a sibling file of the same type could not see, and an `underline()` call that does not exist on
  `AttributedString`), then **two hangs**, `44379381555` and `44384383553`, which are a different kind of
  failure entirely and are recorded in the next section.
- **on-device-verified:** **no.** Not one line of the 14-item checklist below has been run on a phone, so every
  M5 screen here is build-verified and not observed: the drawer and its rows, the swipe actions, Markdown
  rendering against a real answer, the copy buttons reaching the pasteboard, the share sheet, opening a chat
  file handed over by Files, the Local Network prompt's interaction with a LAN server, and what a force-quit
  really does to a temporary chat.
- **real-network-verified:** **no**, and nothing in this milestone needs the network — except that importing a
  chat exported from another device is the one cross-device path worth walking once by hand.

### The hung simulator lane — what actually happened (2026-11-18)

Recorded in full, because two simulator jobs were spent finding this and the next reader should not have to
re-litigate it.

- The run the previous session was waiting on, `44378756616`, **does not exist** — `HTTP 404` from the API. The
  two that really hung are `44379381555` (on `251c387`) and `44384383553` (on `011c1b8`).
- Both died identically: **`Build` green**, then the `Test on iPhone 17 / iOS 26.5` step produced **not one
  line** until the job's own `timeout-minutes` killed it (`##[error]The operation was canceled.`, 20:34:03 on
  the later one). A hung lane is not a failing lane: no test ever reported anything, and a red run would have
  been cheaper than this.
- The lane was silent because that step piped through `xcbeautify`, which buffers its stdout when stdout is not
  a terminal. Proof from the logs rather than from belief: green run `44242238211` emitted its entire 269-line
  test log in one burst at 05:16:28, while the **Build** step of that same job, piping through nothing,
  streamed 4,594 lines live across 20:04 / 20:05 / 20:06. A lane that never exits therefore prints nothing, and
  nothing is the worst possible answer to "where is it stuck". `0ecd1d4` removed the pipe; on that run the test
  step streamed 733 lines inside its first minute and finished in 3m03s.
- The hang itself: `011c1b8` took the scene-less `UIWindow` hosting out of `ChatExportAndRenderingTests` and the
  lane hung anyway, so the window was never the cause. What survived in **every** version of that file, and in
  both hung runs, was `testCopyPutsExactlyTheRequestedTextOnThePasteboard` — a write to `UIPasteboard.general`
  followed by a **read** of it. It is the only call in the whole simulator suite that asks a system daemon for
  anything, and a unit-test bundle with no running app has no foreground process to ask on behalf of. Everything
  else in the file is pure computation or plain file writing, and the identical workspace recipe
  (`SwiftDataStore(inMemory:)` + `MockStreamingProvider.instant` + `.onDeviceOnly`) already passes in
  `ChatConfigSheetTests`. Taking it out of the lane is what made it finish: `44396176219` runs 108 `CairnTests`
  in about two seconds. **That is strong evidence and not proof** — there is no Xcode on this machine, so the
  pasteboard call was never observed hanging, and this is the last candidate standing rather than a demonstrated
  culprit. If the lane hangs again, the log now streams and will name the test it is sitting in.
- Two claims left the suite with it, and neither went without a home: prose-versus-markup is still asserted in
  `ChatExportAndRenderingTests`, and the copy round-trip is line 6 of the device checklist below, where there is
  a real foreground app and a real pasteboard to ask.
- That job's timeout went **30 → 20 minutes.** A green lane spends 3m03s testing inside a job of about five, so
  20 still leaves four times the headroom a slow runner could plausibly need, and a hang now costs 20 minutes
  instead of 30.

### M5 device checklist — run this on the iPhone to close M5 honestly

Each line states what it proves. A pass on one line is not evidence for the next.

1. **Build and run from Xcode on the iPhone** — proves the generated project picked up the new files and the
   document-type keys without a hand-edit.
2. **Open the chats drawer.** Rows newest-first, the open chat marked *Open*, the empty state saying so rather
   than showing a blank list; a search that matches nothing says "No chat has that title."
3. **Swipe a row: Rename, Duplicate, Delete.** Duplicate, then edit one copy — the other must not change, and
   neither may touch the other's nodes. Delete asks first and leaves no ghost row.
4. **Rename a chat to a name containing a slash, an asterisk and an emoji, then export it.** The file that
   appears is dashes and one file — a title must not be able to become a folder or a path.
5. **Ask for an answer with a heading, a bullet list, bold, and a code block.** They render; the code is
   coloured and wraps; **while it is still streaming the text is plain**, and it becomes Markdown when the
   turn ends.
6. **Copy text / Copy Markdown / Copy code.** Prose without the markers; Markdown with them; the code block's
   exact lines including comments. The first must equal what was read, not the syntax.
7. **Tap a link in an answer.** It warns that it opens outside Cairn before it opens. A silent jump is a
   defect, not a convenience.
8. **Stop mid-answer → Continue**, twice. Each continuation extends the same answer
   instead of answering the question again. Then **Start over** on that answer: a sibling is written, the leaf
   moves, and the branch stepper still steps.
9. **Background the app mid-stream and come back.** The answer is marked stopped and Continue is offered — it
   must not look complete, and must not look like it is still streaming.
10. **Export → share sheet → save the `.md` to Notes.** The whole conversation, readable. Then export the
    `.cairn` and import that same file: a new chat, same messages, same order, nothing existing overwritten.
11. **Import a file that is not a chat** — any other JSON. It refuses and says so; the list is unchanged.
12. **Share a `.cairn` to Cairn from Files, then open one from Files twice in a row.** Both import — the
    second must not quietly drop the file because the workspace had not finished starting.
13. **Turn on temporary chat.** The banner and the badge say it; the chat is not in the list; **Keep a copy**
    saves a copy and leaves the temporary chat open and still unsaved. Force-quit: the temporary chat is gone,
    the saved copy is there.
14. **Force-quit and relaunch with a chat open.** The chat and its tree come back, and export wrote nothing to
    disk on the way out.

Any line that fails is a real defect, and its fix belongs in this milestone. The **code-and-CI half of that gate
is met** — green run `44396176219` on `0ecd1d4` — and M5 is closed at that gate. **The checklist is the other
half and it stays owed:** none of 1–14 has ever been run on a phone, so nothing in this milestone is
on-device-verified, and a line that fails on a real device reopens M5 as a defect rather than as scope.

### Gaps carried forward, not hidden

- **`BGContinuedProcessingTask` is not implemented.** A turn that outlives the app is the one M5 item with no
  code behind it. What ships is the honest smaller thing: leaving the foreground stops the turn, marks it
  stopped, and offers Continue. A continued-processing task needs `BGTaskSchedulerPermittedIdentifiers` in
  `Info.plist`, registration at launch, and a runtime check of `BGTaskScheduler.shared.supportedResources`
  for `.gpu`, which the rules say to assume is absent on iPhone — so on iPhone it could only ever be a
  CPU-bound finish, and must not be described as more than that.
- **Markdown renders a whole block, not a diff.** A long answer re-renders when the turn ends: one repaint at
  the end of a stream, not per token. If it is ever seen to stutter, the fix is to cache parsed blocks by text.
- **No highlighting beyond the span table.** Strings, comments, numbers and a shared keyword set for Swift /
  Python / JavaScript / Rust. Anything outside it is plain code, which is correct and uncoloured rather than
  guessed.
- **Inline images are not rendered.** An image line shows its alt text, because fetching a remote image is a
  network decision the app has to make visibly, not one a text renderer makes alone.
- **No view-hosting tests.** The M5 screens are proved by the device checklist above, not by a test. Two claims
  were tried in `ChatExportAndRenderingTests` and both came out: hosting the screens in a `UIWindow` with no
  window scene, because the assertion — a hosted view has a height — is near-tautological; and writing to then
  reading back `UIPasteboard.general`, because it asks a system daemon what a process with no running app should
  not be asking, and it is the last candidate standing for the two hung lanes (corrected account in the section
  above, which also supersedes the earlier guess that the window was what hung the lane). A UI-test target with
  a real window scene is the right home for both claims, and none exists in this project.
- **The list is one screen, not paginated.** `ChatStore.conversations()` returns every chat — fine for the
  hundreds of chats this app is for. If it ever is not, paging belongs in `ChatListQuery`, where the ordering
  already lives.
- **No all-chats export.** `ChatExport.data(conversations:nodes:)` and `ChatTranscript` both take many chats with
  every branch, and the domain is tested for exactly that; what does not exist is a screen that asks for the
  whole set. A user with a hundred chats can only carry them to the share sheet one at a time.
- **No editable title in the top bar.** A chat is renameable from the drawer — swipe a row, then the rename
  dialog — and the top bar shows the title it has, but that title is a `Text`, not a field, so renaming means
  leaving the chat to go and find it.

## M6 — attachments, chunked retrieval with citations, vision gating (**code complete, CI-verified 2026-11-18; device pass owed**)

Spec §3.8. Started 2026-11-18 on the Windows fallback machine, where `CairnChatDomain` compiles and tests but
`CairnPersistence` (SwiftData) and the app (UIKit) do not: that is why nothing was called verified from here,
and why the simulator build and tests were left to CI rather than asserted. The host tests and the simulator
build and tests are now **CI-verified**. What is still not claimed is **on-device-verified** and
**real-network-verified** — no phone has run this code, and no image has been sent to a real server by it.

### What landed — `CairnChatDomain` (compiles and tests on the host)

- `ChatAttachment.swift` — the value a message carries: kind (image/document), the user's file name, the
  declared UTI, the byte count, the bytes, and for a document the text Cairn read out of it here. Plus the
  ceilings (`AttachmentCeilings`) and `AttachmentRejection`, which is the whole vocabulary of "I cannot take
  this file" and why.
- `AttachmentAcceptance.swift` — one function that turns a picked file into either an attachment or a reason
  the user can read. Empty file, wrong kind, too big to hold in memory, too big to send: each says so.
- `DocumentTextExtraction.swift` — plain text, Markdown, CSV and JSON come out as themselves with their
  declared type normalised; anything that needs a real parser (PDF, DOCX) is refused with an instruction to
  paste the text, because guessing at a binary format here would produce a confident wrong answer.
- `DocumentChunker.swift` — a document is cut into passages of ~1,200 characters with 200 characters of
  overlap, on paragraph boundaries where it can be, so an answer can point at a place in a file instead of
  at the whole file.
- `TextTokenizer.swift` — lowercase, fold apostrophes, drop punctuation, emit unigrams and bigrams. Bigrams
  are what make "context window" findable by "window context".
- `LexicalRetrieval.swift` — BM25 (k1 1.2, b 0.75) over the chunks of every document attached anywhere in
  the conversation's visible path, with a query-term guard: a query whose terms appear in no document
  retrieves nothing, and an empty retrieval is reported as "nothing found", never as "here is something
  anyway".
- `GroundedPassage.swift`, `GroundingValues.swift`, `Grounding.swift` — the passage, the citation, and the
  block that gets injected into the system prompt. A citation carries the file name, the chunk index, the
  character range and the score, so a source line still reads after the file is gone from the phone.
- `VisionGate.swift` — one question with one answer: can any engine in play see an image? If yes, send; if
  no, refuse the send and say why. A picture is never quietly dropped, because an answer about a photo the
  model never saw is worse than no answer.
- `ImagePreparation.swift` — the size rule (longest edge 1,568, encoded ceiling 2.5 MB) as a pure decision,
  with `ImagePreparing` as the seam: the domain decides the target, the presentation layer resamples.
  `PassthroughImagePreparer` is the honest no-codec fallback for host builds and tests.
- `ChatTreeAttachments.swift` — the images of the current turn, the documents of the whole visible path, and
  the "can every image still be read" check, all as pure functions over the tree.
- `ChatSessionModel+Attachments.swift` — the session's side of the same rules: `attachmentBytes` (the one
  reader of files), `attachmentStorageAvailable`, `pendingAttachments` (pick → accept → chunk before the
  composer shows a chip), and the two refusal strings the user can actually act on.
- `ChatModels.swift`, `ChatTreeMutations.swift` — a node carries `attachments` and `citations`; edit and
  regenerate carry a user message's attachments onto its new sibling, so editing the text does not silently
  detach the photo.
- `ChatSessionModel.swift` and `+Streaming`, `+HybridJob`, `+ToolTurn`, `+Tools`, `+Config`, `+Continue`,
  `+TreeOps` — the vision gate at every entry point that can send an image, grounding injected into the
  system context by the **same** function used for the preview, images injected only into the turn they
  belong to, and a refusal before anything is written when a stored file has gone unreadable.

### What landed — `CairnPersistence` (written here, never compiled here)

- `AttachmentMetadata.swift` — what a row stores about an attachment: kind, name, declared type, byte count
  and the extracted document text. Never the bytes.
- `AttachmentFiles.swift` — the bytes beside the database, one file per attachment named by its UUID, inside
  the app's own Application Support. Not iCloud, not a shared container, no path from the user's original
  file.
- `Records.swift`, `Mapping.swift` — an `attachmentsJSON` column and a `citationsJSON` column; both read back
  as nothing when the column is absent, which is what a pre-M6 row is.
- `SwiftDataStore.swift`, `SwiftDataStore+Attachments.swift` — bytes are written before the row that names
  them, so a row can never point at a file that does not exist; the citation column is written on the update
  path too, because sources arrive after the row was created; deleting a message or a conversation deletes
  its files, which is the difference between deleting and hiding.

### What landed — the composer, the message row, and the app wiring (second pass, 2026-11-18)

- `ComposerDraft.swift` (`CairnAppUI`) — the files waiting for Send, as one object with the acceptance rule
  inside it. A photo goes through the injected `ImagePreparing` and the chip shows what the codec actually
  produced (new bytes, and a new extension when it re-encoded); a document is read here, on the phone, and is
  staged with the text it yielded; anything refused is refused with the extractor's or the codec's own
  sentence, held on the draft rather than in `lastError` because it belongs beside the paperclip the user just
  pressed.
- `AttachmentPickerMenu.swift`, `PendingAttachmentChips.swift`, `AttachmentChipView.swift`,
  `ComposerAttachments.swift`, `ThumbnailDecoder.swift` — the paperclip (Photo Library and Files as the two
  different things they are, with the plain-text limit stated before the pick rather than after the refusal),
  the staged chips with their remove button, and the three lines the composer can say: a refusal in rust, the
  vision warning in amber, and where these files actually live in stone. A chip whose bytes are gone says so in
  words; an empty box would read as a broken app.
- `ChatScreen+Composer.swift` — Send's three exits in order: nothing to send, the vision gate blocks it and the
  draft stays full, it goes and both the text and the draft clear. The gate consulted here is the session's own
  `visionDecision`, so the amber line above the composer cannot promise something the send two statements later
  refuses.
- `MessageRow+Attachments.swift` — the files under the sentence they came with, read through
  `ChatSessionModel.attachmentPayload` and never off disk from a view; and the sources under a grounded answer,
  in the citation's own numbering, with the file, the chunk, the character offset, the ranking number and a
  short quote, collapsed until asked for.
- `ExportedAttachment.swift`, `ExportedNode.swift`, `ChatTranscript.swift`, `ChatTranscript+Sources.swift` —
  an export describes an attachment (kind, name, declared type, byte count, the text read from a document) and
  carries not one byte of it; an import restores the description and invents no pixels; a transcript says what
  was attached, says the pixels are not in the file, and prints each answer's sources. Moving a photograph out
  of the phone as a side effect of "export the chat" is not a decision the app makes alone.
- `AttachmentNotices.swift` (`CairnChatDomain`) — the two sentences about where a file really lives: a temporary
  chat keeps nothing after the app closes, and a store that could not get a directory keeps a file for this
  session only. Neither blocks a send; both refuse to promise what cannot be delivered.
- `App/AttachmentWiring.swift` — the one place the store's file reader and the session that asks for it meet,
  installed before any session is built, carrying both the reader and the honest answer about storage.
  `App/ImageIOPreparer.swift` — ImageIO against real bytes: read the header without decoding, resample through
  the thumbnail API so a 12 MP photo never becomes a full-size bitmap, check the ceiling against what was
  actually produced rather than an estimate, and rename the file when the bytes changed format.
- `App/CairnApp.swift`, `CairnRootView.swift`, `ChatScreen.swift`, `MessageRow.swift` — the seams handed through
  rather than reached for, so a preview or a test builds with `PassthroughImagePreparer` and no files, and a
  view never becomes a second reader of the conversation's contents.

### The decisions, and the reason each one is there

1. **A file's bytes never enter the database.** Opening a chat reads every message row in it. A photograph in
   a row is read whole on every open, so forty photos in a conversation would make opening it slow in order to
   show text. The row carries name, kind, size and the extracted text; the pixels are read only to draw one
   thumbnail or to send one turn.
2. **An image is sent only on the turn it was attached to, never as standing history.** A photo re-sent on
   every later turn is the same megabytes crossing the user's network for every question they ask afterwards,
   and it is a second copy of the file on the machine at the other end. The node keeps the image so the
   conversation still shows it; the payload goes out once.
3. **A document is never re-sent as a file.** Its retrieved passages go into the system block; the file does
   not. This is what keeps a five-turn-old document from costing bandwidth on turn six, and it is why the
   extracted text is the thing that is stored.
4. **The vision gate answers one question and refuses rather than degrades.** `VisionGate.decide` takes a
   single `modelSees` flag derived from the engines in play. If nothing can see the image, the send stops with
   a sentence naming what to do. An earlier draft of this logic considered sending the text and dropping the
   image; that path is not in the app, because the answer would then describe a picture nobody showed it.
5. **Grounding is built by one function used by both the preview and the request.** Preview and request must
   not be able to disagree, or "show me what you are about to send" becomes a second, prettier lie.
6. **Retrieval is BM25 in pure Swift, no embeddings.** An embedding model is a download the user did not ask
   for and a second model held in memory; the rules say one on-device model unless `os_proc_available_memory`
   allows two. Lexical retrieval answers "what did the file I attached say" honestly, and it is unit-testable
   without a simulator.
7. **A file that has gone unreadable stops the turn.** Regenerate and continue re-read the image of the turn
   they are re-asking. If the bytes are gone, the session refuses with "re-attach the image, or edit the
   message" instead of writing an empty node and asking the model a question it cannot see.
8. **PDF and DOCX are refused with instructions, not guessed.** A hand-rolled parser for those formats would
   return partial text with full confidence; the honest answer is that Cairn reads text files here and the
   user can paste what they need.

### Tests

52 new domain tests, 268 → **320**, all green on the host: `AttachmentAcceptanceTests` (14),
`DocumentChunkerTests` (11), `LexicalRetrievalTests` (12), `GroundingTests` (10), `VisionGateTests` (8),
`AttachmentTurnTests` (13). The last suite runs against `RecordingEngine` / `RequestRecorder` doubles, so it
asserts what actually leaves the device: an image appears in the payload of the turn it was attached to and in
no later turn; a document's passages appear as a system block and never as an attachment; a model that cannot
see never receives the image and the user is told before anything is sent.

Eight more host tests in the second pass, 320 → **328**: `AttachmentExportTests` — the exported file names an
attachment and contains no base64 of it; a message that carried nothing writes what it always wrote (no empty
array); an imported attachment comes back as a description with no bytes; an attachment of a kind this build
does not have is refused rather than guessed at, because image and document differ in what may leave the
device; the transcript says what was attached and says the pixels are not in it; a source line names file,
chunk, character and rank; a citation with no score says nothing about ranking; and the number that ranked a
passage is the number its citation carries.

Twenty-nine new simulator tests (`Tests/CairnTests`, run by the CI test job on iPhone 17 / iOS 26.5), each one
about something a host build cannot answer:

- `AttachmentPersistenceTests` (7) — the file is written beside the row and reads back by the attachment's own
  id; a document keeps its text in the row and its bytes in the file; deleting a message, or the conversation,
  removes the bytes; a row whose file was deleted out from under it survives and says the bytes are gone; a
  store that cannot write fails the save instead of writing a row that names nothing; an in-memory store keeps
  nothing and says so.
- `ComposerDraftTests` (11) — the composer's rules run against the composer: plain text read here and staged
  with what it yielded, a non-text container refused with the instruction to export it as text, an oversized
  file refused before its bytes are looked at, a staged photo being what the codec produced rather than what
  was handed in, a refusal in the codec's own words, non-UTF-8 text refused rather than decoded by guesswork,
  a good pick clearing the sentence about the bad one, removal leaving the others in their original order, and
  `clear` taking both the files and the refusal.
- `AttachmentWiringTests` (5) — the session reads a stored file back through the wiring; a chat started later
  gets the same reader; an unwired workspace says it cannot keep a file while still sending the one in memory;
  a store that could not get a directory passes that on instead of promising; and the composer's warning is the
  same sentence as the send's decision, because both come from the session.
- `ImageIOPreparerTests` (6) — real bytes through the real codec: a 3000×2000 photo comes back with its longest
  side at 1,568, under the encoded ceiling, named `.jpg` because its bytes changed format; a photo that already
  fits is not re-encoded; a PNG keeps being a PNG; prose named `photo.jpg` is refused as unreadable rather than
  as too big; no bytes at all is refused as nothing to read; and a file over the memory ceiling is refused
  before anything is decoded.


### Closure — what the second pass closed, and what is still open

Every item on the earlier list is now code, and the milestone's gate is a CI run rather than an intention.

- **The composer.** A paperclip with Photo Library and Files, staged chips with a remove button, the acceptance
  refusal shown beside the paperclip in the codec's own words, the vision warning before the send rather than
  after it, and the line about where these files actually live. `ComposerDraft.swift` plus four views.
- **The message row.** Chips under the sentence they came with, thumbnails read through
  `ChatSessionModel.attachmentPayload` rather than off disk from a view, and the sources under a grounded answer
  in the citation's own numbering: file, chunk, character offset, ranking number, short quote.
- **App wiring.** `AttachmentWiring.install(on:store:)` gives every session `store.attachmentData` and
  `SwiftDataStore.canStoreAttachments` before it is built; `App/ImageIOPreparer.swift` is the UIKit/ImageIO
  `ImagePreparing` the size rule needed, and it is handed through `CairnRootView` rather than reached for.
- **Export.** `.cairn` carries attachment metadata and citations; the transcript names what was attached and
  says the pixels are not in it. Metadata only, deliberately: bytes leaving the phone as a side effect of
  "export the chat" is a decision the app does not make alone. An opt-in export that includes the files, with
  its own confirmation, is a separate piece of work.
- **Temporary chats.** `AttachmentNotices` says the file dies with the app, next to the paperclip, before the
  send — and blocks nothing, because a file the app cannot keep still rides the turn it was picked for.

**CI-verified — code.** Run `44429557557` on `0f95f62`: guards, host unit tests (328 in `CairnChatDomain`), and
the simulator build plus the 29 new simulator tests on iPhone 17 / iOS 26.5. Getting there took four runs, and
the loop earned its keep. Four compile faults: the composer tests needed `import CairnAppUI`; a `Result` was
being unwrapped with a case used as a member; `fileExists(atPath:isDirectory:)` takes an `ObjCBool`, not an
optional one; and `isWritableFileAtPath` is spelled `isWritableFile(atPath:)` now. Behind the last two sat the
fault actually worth finding. `AttachmentFiles` made its directory with `try?` — the ordinary case being that it
already exists — and `SwiftDataStore.canStoreAttachments` only asked whether a directory had been *handed over*.
A path that was already a file therefore read to the user as "these files are kept on this phone" right up until
the send failed on a write that could never work. `AttachmentFiles.isWritable` now asks the path whether it is a
directory it can write, and the flag the composer states is that answer, so the bad news arrives while the user
still has a choice to make rather than after the send. Disk-full is still found at write time, because nothing
can promise it won't happen halfway through.

**Not on-device-verified.** Nothing in this milestone has run on a phone. The things a simulator cannot answer:
what the Photo Library and Files sheets really hand over on a current iOS, whether a resampled 12 MP photo feels
instant or sluggish on a warm device, whether a large image in a long transcript keeps scrolling smooth, and what
happens to an attachment write when the Local Network prompt or a low-memory kill interrupts it.

**Not real-network-verified.** No image has been sent to a real Ollama or OpenAI-compatible endpoint from this
app, and no grounded answer has been checked against a real server's echo of the injected passages. The domain
tests prove what the request contains by recording it against doubles; they cannot prove a server accepts it.

Still owed, in order: the device pass above; an opt-in "include the files in the export" decision with its own
confirmation; and voice in/out, which stays deferred out of this milestone.

### The device pass, spelled out

None of this is answerable from a simulator, and it needs a phone talking to a real server on the LAN.

1. Pick a 12 MP photo from the Photo Library into a LAN Ollama chat: the chip appears promptly, the staged file
   reads as `.jpg`, and the amber vision line disappears the moment a vision model is selected.
2. Pick that same photo with a text-only model: the send is blocked, the reason is readable rather than merely
   amber, and the pick is not silently dropped.
3. Attach a 2 MB text file and a 30 MB one: the first lands, the second is refused in the codec's own words
   before any reading starts, and nothing is left half-staged.
4. Ask something grounded about a multi-page document: the sources row names file, chunk, character offset and
   ranking number, and those numbers point at the passages the prompt actually quoted.
5. Kill the app while scrolling a long transcript that carries images, then reopen: nothing is missing, and no
   thumbnail had to be rebuilt from an original.
6. Turn on Temporary Chat, attach the photo, send, quit, reopen: the conversation and the file are both gone, and
   the composer said so before the send.
7. Delete the message that carried a photo, then quit and reopen: the message is gone, and the file went with it.
   The file side is only checkable from a container a Mac can see — Xcode's container browser on the simulator,
   or a jailbreak-free device backup — because a phone offers no way to look inside Application Support.
8. Export while offline, and again through the public-internet gate: the `.cairn` opens in both, names the
   attachments, holds no bytes, and the transcript says the pixels are not in it.
9. Run a phone down near a full disk and attach a photo: the failure shows up at the write, says so legibly, and
   leaves no row naming a file that never landed.



### P4 record — LAN model sharing (2026-11-19)

**CI-verified `44466484720` on `b523ca9`.** Privacy guards 53/53; host suites 423 domain + 112 remote +
60 on-device + 17 native, 0 failures; simulator build **SUCCEEDED** and 147 `CairnTests`, 0 failures on
iPhone 17 / iOS 26.5.

Files. Domain (`CairnChatDomain/Share/`): routes and the key table (`ShareRouting`, `ShareDispatch`), a
byte-level HTTP/1.1 reader (`ShareHTTPParser` — CR+LF is one `Character` in Swift, so the head is split on
the LF byte), turn decoding in both dialect shapes with the per-dialect stream default
(`ShareTurnDecoder`), the four response shapes (`ShareStreamEncoder`, `ShareLegacyEncoder`, `ShareReply`),
the pump (`ShareTurnPump`), the policy (`SharePolicy`), the settings and seams (`ShareSettings`,
`ShareServing`, `ShareEngineTable`) and every sentence the surface says (`ShareStatusText`).
Remote (`CairnProviderRemote/Share/`): `ShareSocketTransport` (listener + one client socket),
`CairnShareServer` + `CairnShareServer+Serving`, `ShareTokenHolding`.
UI (`CairnAppUI/`): `ShareModel`, `ShareView`, `ShareView+Selection`, `ShareEntryRow`, and `ServersModel.share`.
App: `App/ShareWiring.swift` (installed from `CairnApp`, scene-phase hook), `project.yml` (the wiring file
compiled into the simulator suite).
Tests: 19 new remote host checks (8 vault, 6 surface, 5 loopback) and 9 new `CairnTests` share checks.

What the exit condition actually got. `ShareLoopbackTests` starts a live `NWListener` on `127.0.0.1` and
drives it with real HTTP: `/api/tags` and `/v1/models` answer 200 only with the key and 401 without it;
`POST /api/chat` streams NDJSON that terminates with `"done":true`; `POST /v1/chat/completions` answers in
its own shape; a model name nobody ticked is refused 404 rather than run against some other engine; and
after `stop()` the port refuses. Loopback only, so CI needs no network and no ATS exception.

Nine things only a real compiler and a real stack taught, each now a rule rather than a note:

1. `NWConnection.ContentContext` has no `.default`. The constant send contexts are `defaultMessage`,
   `finalMessage` and `defaultStream`; body bytes send `.defaultMessage`, the terminator `.finalMessage`.
2. A public default argument may not name a module-internal type, so the "use the phone's own address"
   default lives in a convenience initializer body (`LocalIPv4Reader` stays internal).
3. The key vault is `@MainActor`, because `SecretStoring` is: an actor holding it cannot call the vault
   synchronously. The domain seam is `ShareTokenStoring`, named apart from its concrete holder so a screen
   importing both modules cannot read `ShareTokenHolding` as ambiguous.
4. **An `NWConnection` handed over by a listener is not started.** Reading one waits for bytes that never
   arrive; `serve` now waits for `.ready` before it reads, which is the difference between a phone that
   answers and a phone that accepts and goes silent.
5. A weak capture is bound as a **var**, so a nested `@Sendable` closure may not read it — the surface is
   copied to a constant once at the top of the detached task.
6. `NWListener(using:on:)` **rejects** parameters carrying `requiredLocalEndpoint`: on the CI runner the
   bind failed in under a millisecond, and every loopback test skipped. The transport now tries the pinned
   bind first and falls back to a device-wide bind, and reports which it got as `ShareBindScope` — the
   screen prints that sentence, because the address line alone would claim a guarantee the system did not
   grant. The two rules that do the real work did not move: no private LAN address, no start; no key, no
   answer.
7. **A head that promises a `Content-Length` has to deliver the body.** The pump ran buffered turns through
   a head-only sink call, so the socket closed with the length unsatisfied and URLSession reported
   `-1005, the network connection was lost`. `ShareFrameWriting.writeHead` is now `writeReply`: head and
   body in one send, so the mistake cannot be made again by a caller who forgets a line.
8. `private` in Swift means file-private: `ShareView` holds its model module-internally because the picker
   is a second file — the same reason `ServersModel` keeps its state module-internal for `+Discovery`.
9. XCTest assertions take autoclosures, which do not run concurrency: `await` goes into a name first.

The key. Generated, never typed, at least 16 characters by policy and 32 in practice, stored under the
Keychain service `app.cairn.share-key` with `.afterFirstUnlockThisDeviceOnly` — **a different service from
`app.cairn.server-token`**, the vault that holds the tokens this phone presents to other machines. Two
directions of trust, two namespaces, tested both ways: a share key is not readable as a server token, and a
server token is not readable as the key that opens this phone. Rotation is the revocation button, and the
screen says out loud that old clients stop working.

Still owed, in order:

1. The device pass below, on a phone on a real Wi-Fi network.
2. A real client against the phone: `ollama -h http://<phone>:11434 list`, one streamed chat from the Ollama
   CLI, one OpenAI-SDK completion, and one browser hitting `/api/version`. **The preflight question is open,
   and the record says so rather than pretending otherwise:** `ShareHTTPResponse.preflight(origin:)` answers
   204 and echoes the requesting origin back in `Access-Control-Allow-Origin`, which is a *grant* — it is what
   lets a browser-hosted client (Open WebUI and friends) use the phone as its Ollama, and it is also the one
   place where "a local network is your network, not an empty one" is looser than it reads. Nothing is served
   without the key, and no wildcard `*` is ever sent, so the exposure is bounded by the key. Whether to
   narrow it — a switch, an origin list, or a plain refusal — needs a real browser in the loop to say what a
   real web client requires, so it is listed here and not changed blind.
3. Whether iOS reports `chosenAddress` or `deviceWide` — the caveat sentence is already written for both.

### The device pass, spelled out

1. Turn sharing on with no server configured: the switch comes on, the status line names the port, the
   address line shows an address, and the key row shows a masked key with Copy and Regenerate.
2. Turn it on with nothing ticked to share: the switch snaps back and the sentence says nothing is ticked,
   rather than the screen going quiet.
3. First connection from a laptop: iOS raises the Local Network prompt; denying it really does stop the
   client, and the screen's permission line is what the user has to find.
4. Copy the key into a laptop and ask for the model list: it answers. Delete the key from the laptop's
   request: 401, and the model list is not discoverable without the key.
5. Regenerate the key while the laptop is configured: the laptop stops working immediately.
6. Stream a shared answer from the laptop: tokens arrive as they are produced, the client ends cleanly, and
   the phone's status line says "answering now" while it happens.
7. Turn sharing on, then background Cairn: within moments the client stops reaching the phone, and when
   Cairn comes back the switch is off with the sentence that says why. Nothing re-opens itself.
8. Share an engine that is a remote server: the laptop's request is answered by that server, and the screen

## Task B — Web search providers: DuckDuckGo default, own SearXNG, Ollama Cloud (**closed 2026-11-19**)

Against `docs/CLEANROOM_SPEC.md` §7. Three slices, all coded, and now green: **CI
[44567976658](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/44567976658)** over `f7a4f77` — guards
53/53, host suites 492 domain + 170 remote + 60 on-device + 17 native, simulator build **SUCCEEDED** and 171
`CairnTests` with 0 failures. It took **ten red runs** the same day — `44484030860`, `44490538639`,
`44492059473`, `44498516568`, `44505415512`, `44508652621`, `44510185732`, `44513378138`, `44515633028`,
`44518294831` — to get from the first Task B commit to that green one. The causes fall into six classes, and
every one of them was invisible to a check this machine could run; they are recorded below rather than smoothed
over.

- **Slice 1 — `7f76c50`** (domain, persistence, failure taxonomy). Provider rows instead of one routing
  switch: exactly one row is active, there is no fallback, and a failure is named rather than answered with
  "nothing found". `SettingsRecord` also stopped losing `webTools` on relaunch, and a pre-provider SearXNG
  address imports itself as a row on the first read after an upgrade.
- **Slice 2 — `c9187b8`, `87cc06c`** (consent, the failure suites, the wiring that still pointed at the old
  model). Consent is asked before the request is built, a refusal costs no socket, nobody-to-ask is a denial,
  a stored no is an answer, and a challenge page is `blocked`.
- **Slice 3 — `7ce6cff`, `6b2a079`, `ef9e84e`** (the settings screen, the sheet, the app layer that joins
  them). `WebSearchSettingsScreen` (provider picker, own SearXNG address, result count, Test Connection),
  `WebSearchConsentSheet` + `WebSearchConsentModel` handed to `WebSearchConsentRequester`, and
  `App/WebSearchWiring.swift` binding settings, Keychain and the sheet. The SwiftData `webSearchJSON`
  round-trip is now covered on the simulator lane by `WebSearchSettingsPersistenceTests`, and the join itself —
  consent, provider rows and the two Keychain vaults meeting in one object — by
  `WebSearchConsentWiringTests`.

### Why CI run 98 was red on `ef9e84e`, and what it changes

`WebSearchFailure+Transport.swift` read `error.posix?.rawValue == 1` to guess the Local Network refusal.
**Apple's `URLError` has no `posix` accessor** — the symbol is absent from Apple's `URLError` symbol graph and
`/documentation/foundation/urlerror/posix` is 404 — so that line has never compiled on macOS. It compiled
here only because the local throwaway tree shims Apple-only spellings to get the module to build on Windows;
the shim hid a real error instead of catching it. Two lessons, both now in the code:

- The read is portable and honest: `error as? URLError`, then the bridged `NSError` — its own domain, or the
  one under `NSUnderlyingErrorKey` — under `NSPOSIXErrorDomain` with errno `1` (EPERM). Still labelled a
  guess, still the only guessing line in the file, and `URLError.Code(rawValue:)` is not used because it is
  non-failable on Darwin and failable on the portable Foundation — a compile difference, not a runtime one.
- `WebSearchFailureTransportTests` (9 assertions) pins the mapping: each certificate code says
  `httpsRequired`, each status line says its own thing, a `EPERM` underneath says `localNetworkDenied`, and
  the two ways it must **not** be claimed — right errno under the wrong domain, right domain with the wrong
  errno (ECONNREFUSED) — stay `unreachable`.

What remains unverified is the thing no host test can reach: **what iOS 26 actually returns when the Local
Network permission is denied.** That stays on the device checklist, and the guess is allowed to be wrong about
the shape while never being silent about the failure.

### What Slice 2 decided, and why

- **Consent is asked before the request is built.** The tool cannot present a sheet, so the app hands it a
  `@MainActor` requester. A refusal costs no socket, no bytes, no latency, and it is a typed
  `internetNotAllowed` — the model reads a person's decision, not a broken tool.
- **Nobody to ask is not a yes.** A preview, a test host, or a build with no sheet gets the "Cairn has to ask
  first" refusal. The default is denial, because the alternative is a silent grant the user never gave.
- **A stored no is an answer.** A declined row is refused without asking again, so "no" cannot be worn down
  by a persistent model. A row on the user's own network is never asked about at all: it is not a third
  party, and a sheet that asks nothing trains people to tap through a warning.
- **A challenge page is `blocked`.** The endpoint answers a bot check with an ordinary page and a 2xx status;
  read as markup-with-no-results it would have become "nothing exists". Result anchors still win over the
  words — someone may legitimately search for "captcha".
- **The cache key is the domain's key.** `WebSearchCourtesy.key` covers provider, normalized query and every
  parameter that can change the answer; the cache stays in memory, because a stored record of what the user
  searched for is the kind of side file this app must not create quietly.
- **Two vaults, one direction.** A cloud row takes its key only from the server profile it mirrors; a LAN
  server's API token is never handed to a search row, and a row that declares no credential is handed
  nothing at all.

### The ten red runs before this green one, in six classes

Ten runs were red between the first Task B commit and `44567976658`. The causes below are the ones I read in a CI
log or reproduced myself. The three earliest runs (`44484030860`, `44490538639`, `44492059473`) are attributed
from the fix commits they prompted (`8508a7b`, `dc9ed03`, `29b05b8`) rather than from a log opened in this
session, and that difference is stated rather than glossed over. `swiftc -parse` accepts all of this code and the
scratch-tree host build accepts most of it, which is the point: the lesson is the blind surface, not the fix.

1. **`URLError.posix(_:_:)` does not exist** (run 98) — a line written here that could only ever compile here.
   Now `URLError(domain:userInfo:code:)` with the code and `kPOSIXError_EPERM` carried in `userInfo`, which is
   what `posix` used to do internally.
2. **Swift 6 rejects a `catch` that swallows every error as unhandled** (run 44515633028) — nine sites, each of
   which had to be given a typed reason of its own rather than a bare `catch { }`.
3. **Actor isolation, not syntax** (run 44515633028) — `Sendable` boxes for the Keychain vaults handed across
   the seam, and `@MainActor` on the objects that own UI state. Parsing cannot see either.
4. **`private` and `private(set)` are file-scoped in Swift** (run 44518294831, build) — four AppUI files split
   an extension across files and so could not see their own type's storage; the UI models now carry
   `public internal(set)`, and an environment property declared in an extension had to lose its `private`.
   `Section("title") { } footer: { }` is also not a signature SwiftUI offers; it is
   `Section { } header: { } footer: { }`.
5. **Two names that were never written** (run 44518294831, build) — a `GuideBlock` view and a
   `CairnTheme.stone950` token, both called by the SearXNG guide sheet and neither defined anywhere.
6. **Seven tests red inside a lane that finally ran** (run 44518294831, tests) — and only one of the three
   causes was a product bug:
   - **Four** came from a test helper that built its **own** `ThemeModel` from a settings snapshot, so the
     consent seam answered through one model while the assertions read another. The grants and refusals really
     were filed — into an object the test never looked at. The helper now takes the caller's model, which is how
     the app installs it. That suite was never capable of noticing a missing join, which is the only bug it was
     written to catch.
   - **Two** asserted `.undecided` for a row on the example LAN address. `decision(for:)` reports any row that
     does not reach the public internet as **granted**, because a box on your own network is not a third party
     and asking about it trains people to tap through a warning that warns about nothing. The expected value was
     therefore unreachable, and the tests were not testing revocation at all — they were reading a value the
     design produces whatever the revoke logic does. Revocation was correct and untouched; the tests now use a
     public `https` row, where a grant is a real grant and taking it back can be observed.
   - **One** was a stale expectation about storage: a pre-P3 settings row used to read back with no web-tool
     value, and Task B made the provider store unconditional. What mattered was never "the field is absent" but
     "nothing the user never chose got invented", so the assertion says that field by field now. Comparing the
     whole `WebSearchSettings` against `.default` was tried first and rejected: provider rows carry
     `createdAt`/`updatedAt` defaulting to `Date()`, so two defaults built microseconds apart are unequal and the
     test would have been measuring clocks.
   - Two steps in the consent suite also settled async work with fixed sleeps, which is how a suite passes on a
     quiet machine and hangs a loaded CI runner. They wait on the condition with a timeout now, not on the clock.

### Verification, by tier — the tiers do not substitute for each other

- **Local, host:** `swift test --package-path Packages/CairnChatDomain` — 492 tests, 0 failures.
  `Scripts/ci.sh guards` and `Scripts/test-guards.sh` — 53 ok, 0 failed. `Scripts/parse-check.sh` — 565 files
  parse clean.
- **The remote module now does compile here, in a throwaway tree — and that is not a milestone.**
  `CairnProviderRemote` imports `Security` and uses Darwin-only `URLSession` spellings, so it cannot build in
  place on Windows. A scratch copy outside the repo (`/tmp/rc/remote`) with `swift-tools-version` at 6.0, a
  `#if canImport(FoundationNetworking)` import added per file, and the handful of Darwin-only setters
  neutralised builds the module and runs **148 tests, 0 failures**, including the 9 new transport assertions.
  That tree proves Swift 6 concurrency and logic; it does **not** prove Keychain, SwiftUI, the simulator lane,
  or any Apple-only API spelling — which is exactly the class of error it hid once (see the run 98 note
  above), so its results are cited as host checks and never as a green lane.
- **CI-verified:** **yes — [44567976658](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/44567976658)**
  over `f7a4f77`, all three jobs green. Privacy guards 53/53. Host lane: `CairnChatDomain` 492 tests and
  `CairnProviderRemote` 170 (XCTest), `CairnInferenceLocal` 60 tests in 14 suites and `CairnInferenceNative` 17
  in 2 suites (Swift Testing — worth knowing that those two report in a different format, so a grep for
  `Executed N tests` reads them as **0** and a suite that ran nothing would look identical). Simulator lane:
  build **SUCCEEDED** and `CairnTests` **171 tests, 0 failures** on iPhone 17 / iOS 26.5. This is the first
  green run any Task B suite has, so every citation above that predates it is host-verified, not CI-verified.
- **A guard hardened, because it had a hole:** `parse-check.sh` scanned `App`, `Packages/*/Sources` and
  `Tests`, so nothing in `Packages/*/Tests` was parsed at all; and parsed as one module, a missing `}` at the
  end of a file is absorbed by the next file. It now scans the package test directories too, and re-parses
  every file the working tree has touched on its own. That second pass is what found the unclosed class
  `WebSearchToolTests.swift` had been carrying.
- **What no host check on this machine can see:** Keychain behaviour, SwiftUI view behaviour, the simulator
  lane, and any Apple-only API spelling. Those belong to CI and to the phone, and the run 98 note above is
  what that blind surface cost once — a line that only ever compiled here.
- **On-device-verified:** no. **Real-network-verified:** no — no real DuckDuckGo endpoint was reached, no real
  SearXNG instance was queried, and no real `POST /api/web_search` was sent with a real key. The checklist at the
  end of this file is what closes those two tiers. A green simulator lane does not stand in for either: it never
  shows the Local Network prompt, a badge in a real status bar, a `403` from a real bot check, or a Keychain item
  that survives a reboot.
- **Transport, restated because it is the part a reader will want to argue with:** nothing in Task B assumes a
  mesh VPN or requires TLS to a private host. A server on the user's own network is reached over plain `http://`,
  and a person who serves models on that network has already said that a client reaching this phone reaches that
  server too. Away from home it is the tunnel, not a certificate, that protects the path — which is why the code
  classifies destinations instead of encrypting them, and why a plaintext row carries a visible badge rather than
  a silent ATS exception.

### Task B device checklist — run this on the iPhone and on a real network

A green simulator lane proves the logic and the build. It does not prove any line below. Each item says what it
proves; a pass on one is not evidence for the next. Record what the phone actually did, not what was expected.

1. **Build and run from Xcode on the iPhone.** Proves the generated project picked up the consent sheet, the
   settings screen and `GuideBlock` with no hand-edit to `Cairn.xcodeproj`.
2. **Arm a web tool and ask the built-in provider a question.** The sheet appears **before** any result, naming
   the provider and saying the query leaves the device. A result that arrives with no sheet is the defect this
   whole task exists to prevent.
3. **Answer No.** The turn answers with the typed refusal rather than a spinner or a "tool broke" message, and a
   second search in the same chat does not ask again.
4. **Answer Yes, then search again.** No second sheet. The outbound badge appears and stays up for the rest of the
   conversation, including after leaving the chat and reopening it from the list.
5. **Ask something that needs a page read.** It is its own question. Answering it once covers reads to a
   different host later; a search grant alone must **not** have answered it.
6. **Close the sheet without answering.** Counts as No and is recorded, and the next turn does not ask. Walking
   away cannot read as agreement.
7. **Deny Local Network in iOS Settings, then search a LAN row.** Read out exactly what the app prints. The
   labelled Local Network refusal only appears if the errno evidence is really there; if it prints `unreachable`
   instead, that is the honest answer and the guess stays labelled. **This item decides whether the EPERM guess
   is right — write down which one it printed.**
8. **Add your own SearXNG row on the LAN over plain `http://`, then Test Connection.** It saves, the `Plaintext`
   badge shows on the row, no ATS exception was needed, and the first request raises the iOS Local Network
   prompt. If iOS blocks it, that is the denial-with-no-retry case, not a bug to code around.
9. **Search through that row.** Results come from your instance, the result names the row that produced them, and
   nothing goes to the public endpoint while that row is active.
10. **Move that row's address to another host.** The permission returns to undecided and the next search asks
    again — a grant must not travel with the row to somebody else's instance.
11. **Delete the row.** Its key is gone from the Keychain (re-add the same row and it asks for a key again), and
    the app says it reverted to the built-in provider rather than quietly searching somewhere else.
12. **Away from home, over your own WireGuard tunnel.** The tunnel address reaches the same server over plain
    `http://`, and the badge still tells private-network traffic and public-internet traffic apart honestly.
13. **Hit a site that answers `403` or a bot check.** The tool says it was blocked — not "nothing found", not a
    crash. A confident empty answer is the failure mode here.
14. **With an Ollama Cloud row and a real key:** the query goes to Ollama's endpoint with that key and no other
    row's credential, and a LAN server's bearer token is never used as a search key.
15. **Kill the app mid-conversation, reopen it, and reboot the phone.** Consent records, provider rows, the active
    row and the page-read answer all come back; the Keychain item survives a reboot and does not survive a device
    wipe.
16. **Airplane mode, then search.** It reads as offline — not as a refusal, not as a broken tool, not a hang.

**What closing this list would mean:** on-device-verified and real-network-verified could be cited for Task B.
Until then Task B is closed at the CI gate only, and that distinction is the whole point of the list.

## Device bug round — four fixes before the next IPA (2026-11-19)

Four things a phone reported that the simulator lane could not see. Each one is now a rule with a test
where the rule can be pure, and none of them is claimed `on-device-verified` until the list at the bottom
of this section has been run on the phone.

1. **One tap on `Tools` arms the chat.** `ToolChipRule.tap(chipIsUp:outboundWebAllowed:)` decides the tap,
   and it decides only *up or down*. What a backend claims to support never enters that decision — a
   server with no native tool calling is still handed the tools, through `PromptToolProtocol`
   (`ToolRouting.format` decides *how* a call travels, never *whether* the user may arm a chat). The
   outbound acknowledgement is still asked, with both ways out, but it now travels **with** the arming
   instead of standing in front of it: a tap that opened a question and left the chip unfilled read, on a
   phone, as a dead button, and a dialog dismissed by reflex left the chat unarmed with nothing to show for
   the tap. The value a tap writes is `ToolToggleSet.armed`, not `.default` — the shipped default has the
   chip **down**, so writing it was a tap that changed nothing, which is the actual defect.
   Test: `ToolChipRuleTests`.
2. **Every step of a tool loop carries its tools.** `ToolLoop` rebuilt each continuation
   `GenerationRequest` from `modelID` / `messages` / `config` alone, so a second step reached a native
   backend with no `tools` array: the first turn was answered from the block in the system message, and
   every step after it had nothing to call. Steps now carry `tools` and `toolProtocol`.
   Test: `ToolLoopStepRequestTests`.
3. **`Force Web Fetch` is a switch again.** `TurnContext.webFetchActive` was written `false` on every path,
   so the key in the configuration sheet moved a conditional block that could never be live.
   `ContextAssembly.webFetchIsLive(toggles:offered:)` requires the switch to be on **and** a web tool the
   model was actually offered this turn — a web tool the acknowledgement has not released is already
   removed by `ToolRouting`, and a block that says "a web search ran" must not ride on a calculator-only
   turn, because a model told to cite a page it was never offered invents one. The flag now travels on the
   continuation steps with the tools. Test: `WebFetchLivenessTests`.
4. **A theme reaches every window.** Each screen used to resolve its own paint, and any window that forgot
   fell back to the environment default — one fixed dark palette — so the transcript recoloured while
   Settings, Servers, the chat list and every editor behind them did not. `CairnChromeStyle` is now the one
   place paint is resolved; `CairnSheet` gives a presentation its own themed stack instead of a bare
   `NavigationStack`; and `CairnChromeModifier` paints the tint, the canvas, the nav bar, the list's own
   background and the sheet material — inside a presentation's stack, where a bar actually reads its styling
   from, and outside it, so a pushed screen inherits the paint rather than meeting the default.
   Test: `ThemePropagationTests`.

### The concurrency rule this round cost a CI cycle

A `ViewModifier`'s `body(content:)` is **not** main-actor isolated in the iOS SDK, while `ThemeProvider`
and the settings object are. So `@MainActor` helper methods called from `body` are Swift 6 concurrency
errors — and putting `@MainActor` on the modifier type is a *different* error, because it then cannot
witness the nonisolated `body(content:)` requirement. The form that compiles: a `ViewModifier` stores
**values** and does no isolation-sensitive work inside `body`; the resolving happens in the `View` extension
method that builds it, which is main-actor work. `CairnChromeModifier` therefore holds a `CairnPalette?` and
an `AppearanceMode?` and nothing else, with the scheme / pin / token resolution as three nonisolated computed
properties over those two values.

### What the per-tool menu still does — correcting the record

`7397156`'s commit message said a per-tool web switch "arms on its own tap and confirms only against the
state that tap changes". **That is not what shipped, and this is the record of what did:** a web switch in
`ToolSwitchMenu` stays **disabled** until the outbound acknowledgement is up. That is deliberate — the
acknowledgement is asked once, by the chip, with both ways out, and the menu reports state rather than
re-asking it. A menu that asked per switch would put the same disclosure in front of the user five times.

### Verification — the three categories, not merged

Locally (Windows, host toolchain): guards 53/53, `CairnChatDomain` 552 tests green, `Scripts/parse-check.sh`
clean across 573 files. `CairnProviderRemote` cannot build here at all — `import Security` has no Windows
module — so its lane is CI's, as are `CairnAppUI` and the simulator suite.
CI [`44599188881`](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/44599188881) on `4353030`: **completed, success**
— Privacy guards, Host unit tests (macOS), and **Build + test on simulator** all green. The simulator job is
the lane that compiles `CairnAppUI` and runs `ThemePropagationTests`, and it is the run the four
`docs/PARITY.md` rows updated in this round cite.
Not `on-device-verified`. Not `real-network-verified`. The CI gate for a fresh unsigned IPA is met on this
commit; `ipa.yml` is a `workflow_dispatch`, so the user triggers the build.

### Device checklist for this round — five lines, each says what it proves

1. **Tap `Tools` on a chat whose web acknowledgement is down.** The chip fills **on the tap**, before any
   dialog, and the dialog offers both ways out. "Only tools on this device" leaves the chip up with the
   calculator and the mail draft; the web switches beside it stay dimmed and say why.
2. **Arm it on a server that does not advertise native tool calling, then ask something a tool should
   answer.** The prompt protocol runs the call, or the answer says it could not. Silence is the failure this
   fix was for, and it is why the chip no longer consults capability.
3. **Switch `Force Web Fetch` on and open the context preview.** The block appears on a turn with a web tool
   offered, and does not appear on a calculator-only turn, nor on a turn whose web tool the acknowledgement
   has not released.
4. **Change theme and appearance, then open every presentation**: the chat list, servers, settings, the chat
   configuration sheet, the web-search screen and its provider editor, the SearXNG guide, the servers guide,
   and a web-search consent sheet. Each shows the chosen accent, canvas and nav bar; none shows the system's
   card background or the old fixed amber.
5. **Kill the app with a web tool armed and a badge up, then reopen it.** The chip comes back up, the
   acknowledgement comes back, and the badge is still read back off the stored node rather than off the live
   turn.

## P6 — `get_location`: what is proved, and what a phone still owes

**CI-verified** on `a02eb51`, run [44634743108](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/44634743108):
Privacy guards green with the guard self-test at 53/53; Host unit tests on macOS — 535 domain + 170 remote, 0
failures; Build + test on iPhone 17 / iOS 26.5 — the build compiles `LocationProvider`, its mapping extension,
`LocationWiring`, the consent model and the consent sheet, and **190 `CairnTests` run with 0 failures**, 14 of
them written for this seam (9 wiring, 5 mapping).

**Host-verified** on the Windows authoring machine: 535 domain tests green, guards 53/53, 593 files parse clean.
That machine compiles none of the CoreLocation or SwiftUI code — no `Security`, no `CoreLocation`, no XCTest on
macOS — so its numbers describe the pure half, and the pure half is exactly where the consent state machine
lives.

**On-device-verified: no.** **Real-network-verified: not applicable** — a position read opens no socket, the
tool's `NetworkClass` is `.onDevice`, and there is no badge, no outbound opt-in and no geocoder in the binary's
path for this tool.

### Device checklist for `get_location` — six lines, each says what it proves

1. **Ask a model where you are with the `Tools` switch on and location never answered.** The consent sheet comes
   up first and Location Services stays dark while it is up. The entire privacy claim is that ordering, and only
   a phone can show that no radio woke.
2. **Answer no.** The next turn is answered from the record with no sheet, and System Settings still says Cairn
   has never asked. A dismissed sheet counts as a no too.
3. **Answer yes, then answer iOS's own prompt.** Two different questions, two different no's: ours asks whether
   Cairn may use your location, iOS asks whether this app may, this time. A yes to ours and a no to iOS's has to
   come back as "no position" — not a crash, and not a position invented from the network.
4. **Kill the app with the sheet up, then reopen it.** Nothing about a position survives, a fresh chat asks
   again, and no half-finished read is replayed from storage.
5. **Switch Cairn's system permission to Never while our record still says granted.** The tool answers "no
   position" with one attempt and no retry loop, and it must not report a person's decision as the cause — iOS's
   denial does not rewrite our record.
6. **Read a position with a weak indoor fix and ask a model what place that is.** The tool hands over numbers
   and an accuracy radius and nothing else. If the answer names a town, the model invented it, which is why no
   geocoder is linked in.

What closing this list would mean: `on-device-verified` could be cited for P6. It changes nothing about the CI
claim, and no amount of device checking turns the counting fake into a radio — that gap is the reason the two
tiers are reported separately.


## 2026-11-19 — five reported faults from using the app: a bare tool row, an empty model list, a mode that explains nothing, an on-device turn that dies, a keyboard that owns the screen

**Host-verified** on the Windows authoring machine: 574 domain tests green (10 written for this pass), guard
self-test 53/53, `Scripts/parse-check.sh` 604 files parse clean. That machine compiles none of the SwiftUI or
FoundationModels code — no `SwiftUI`, no `CryptoKit`, no `FoundationModels`, no XCTest on macOS — so the on-device
provider and every view edited here are **not compiled locally**, and `parse-check` is syntax only. A second reviewer
pass checked the Apple-framework surface for the things a parse cannot see; two of its findings were taken (the
`presentationCompactAdaptation` modifier belongs on the presented content, not on the presenting control; a keyboard
accessory bar item is collected from the screen's toolbar, not from a nested subview) and two were rejected against
evidence in the tree — the pre-existing, CI-green call site already passed a `String?` into
`LanguageModelSession(instructions:)` and a `String` into `streamResponse(to:)`, so those two shapes are proven here
and were left alone.

**CI-verified: yes — run [44652196582](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/44652196582) on `e203fca`,
completed success.** Privacy guards green with the guard self-test at 53/53; Host unit tests on macOS — **574 domain +
170 remote + 60 on-device + 17 native, 0 failures**; Build + test on iPhone 17 / iOS 26.5 — build green, **193
`CairnTests`, 0 failures**. The claim is pinned to `e203fca` and not to `1412473`: the run on that commit
(`44652085134`) was **cancelled** 1 m 13 s in when this commit landed, so nothing before `e203fca` finished a suite at
all, and the only citable number for this pass is the one above.
**On-device-verified: no.** **Real-network-verified: no** — the routing change repoints a chat at a server, and only a
phone on a real LAN can prove that tap.

### The five faults, and what each one turned out to be

1. **A tool row with no mark.** `BuiltInTool.getLocation` mapped to `location.pin`, which is not an SF Symbol name. A
   wrong symbol name is a string that compiles, runs, and draws nothing — so the row arrived as a switch with no
   glyph and no explanation. It is `location.fill` now, and `ToolSwitchLabels.allSymbols` exists so a test can ask
   UIKit whether every name this type can return actually resolves. That is the only way this class of bug is
   catchable without eyes on a screen.
2. **A model list with nothing in it.** `OnDeviceEngineReport` now says which engine choices exist and why an empty
   one is empty; `LocalModelLibrary` and `LocalCatalogQuery` hold the Hugging Face rows and the query rules (a repo
   with no `gguf` is not offered, and a repo already pulled is named as already pulled). An empty list is a state with
   a reason, not a spinner that never resolves.
3. **A mode that says four words and means nothing.** `InferenceMode+Explainer` carries a title, a one-line note and a
   full explanation per mode — who runs the answer, and whether a byte leaves the phone. The switcher menu shows the
   note under the name; the `(i)` beside the pill opens the full text as a popover that stays a popover on iPhone.
4. **An Apple on-device turn that fails with a red line.** `PromptContextFit` fits the prompt to a declared 4,096-token
   ceiling before the request is built — oldest turns first, then the tool block, never the question just asked — and
   `contextTokenCeiling` on `InferenceProvider` is what makes the ceiling a fact the composer can state rather than a
   number the settings sheet implies. A turn that cannot fit at all refuses with its own sentence; availability reasons
   stay distinct (`Apple Intelligence is switched off` and `this iPhone cannot run it` have different fixes), and
   `OnDeviceGenerationError` conforms to `LocalizedError` so the reason survives the trip to the composer's error
   line instead of arriving as `error 3`.
5. **A keyboard that cannot be closed.** The composer grows to four lines and no further, scrolling the transcript
   dismisses the keyboard with the finger already moving, and there are two ways to close it: `Done` in the keyboard's
   own bar, and a chevron in the row that only exists while the keyboard is up.

### The fault underneath four of them: a control that does not do what it says

`ModeRouting` is new and pure. A mode is a routing decision, so `On device` now repoints the session at an engine whose
declared `engineKind` is `.localModel`, and `Remote server` at the engine built from the *chosen* profile — not the
first server in a list. `ChatWorkspace+ModeRouting` carries out that decision through the same call a hand-tap on the
model menu takes, so the model list, the outbound badge and the saved per-server model behave exactly as they do when a
person taps. Hybrid modes repoint nothing: a hybrid turn names both engines in its own plan. A mode with nothing behind
it changes nothing and invents no engine; the existing refusal is what the user reads. The distinction `NetworkClass`
cannot make — a stand-in and a real on-device model are both honestly `.onDevice`, and only one of them runs a
model — is why `EngineKind` exists at all.


### What the 574 green host tests actually cover here

`ModeRoutingTests` (8) — that `On device` names the on-device engine and never the stand-in, that `Remote server`
names the *chosen* profile rather than the first server, that a mode with nothing behind it and a mode already honoured
both repoint nothing, that hybrid modes repoint nothing, and that an unknown engine id reads as a stand-in.
`PromptContextFitTests` — the fit order (oldest turn first, tool block before the question just asked), the
512-token response reserve, and the refusal when nothing can be dropped and it still does not fit.
`EngineCapabilityNoteTests` (10) — that a thinking switch on an engine with no reasoning trace says so and names the
engine, that a tools switch on an engine with no tool schema says the tools arrive as text, that switches at rest say
nothing, and that the window note appears for an asked window above the ceiling and for an unset window, and never for
an engine that states no ceiling.
`InferenceModeExplainerTests`, `LocalCatalogQueryTests` — the copy and the catalog rules they are named for.

What no host test can reach: that the popover stays a popover on a phone, that the keyboard bar item appears at all,
that the fitted prompt is the one Apple accepts, and that a repointed session answers from the machine it now names.

### Device checklist — five lines, each says what it proves

1. **Open the Tools switch list on an iPhone 15 Pro.** Every row carries a mark. A row with no glyph means an SF Symbol
   name that does not resolve, which is the fault being closed; `Scripts` cannot see this and `allSymbols` in a UI test
   can.
2. **Start a chat on a server, then choose `On device` in the mode menu and ask something.** The answer must come from
   Apple's model — the model pill changes, and the composer's capability line appears saying that engine emits no
   reasoning trace. If the pill still names the laptop, the mode is a label again and `ModeRouting` did not fire.
3. **Choose `Remote server` with two servers saved and the second one active.** The pill must name the second server's
   engine, not the first, and the model that server was last used with must come back.
4. **On device, paste a long document into a chat with Tools on and ask a question.** The turn must either answer, or
   refuse with the context sentence naming the 4,096-token ceiling — never a red line that says nothing. Then shorten
   it and watch it answer: the trimming is supposed to be visible, and the ceiling note in the header has to match what
   the turn actually did.
5. **Type a message with the keyboard up, then scroll the transcript down.** The keyboard travels with the finger;
   `Done` in the keyboard bar closes it; the chevron in the composer row closes it; and after closing, the keyboard does
   not come back until the field is tapped again. The composer must not push the newest answer off the top of the
   screen at four lines of typing.

What closing this list would mean: `on-device-verified` could be cited for this pass, and a CI run number on the same
commit for the half the Windows machine cannot compile. Neither turns the 4,096 figure into a measured number — it is a
declared ceiling, because the framework offers no way to ask, and it stays a declared ceiling in every sentence the app
says about it.

## 2026-11-19 — every changeable setting gets an `(i)`: a catalogue in the domain, a card that floats, and two controls that never existed

**Host-verified** on the Windows authoring machine: **585 domain tests green** (the previous pass's 574 plus the catalogue's
own assertions), guard self-test **53/53**, `Scripts/parse-check.sh` **617 files parse clean**, and the logging, signing,
ATS, hostname and zero-paywall guards green. That machine compiles none of the SwiftUI code — `CairnAppUI` is iOS/macOS
only, so **nothing edited here is type-checked locally** and `parse-check` is syntax only. A reviewer pass over the
Apple-framework surface took four findings and rejected none outright: the glyph's tap area needed
`contentShape(Rectangle())` over a 28-point frame, because a fifteen-point hit sitting beside a toggle is worse than a miss
in empty space — the miss lands on something that changes state; a bare `ScrollView` has no intrinsic height and a popover
sizes to what it is given, so a two-line explanation arrived as a full-height card, now `ViewThatFits` with the scroll view
as the fallback; `presentationDetents` is ignored the moment the content adapts to a popover, so it was deleted rather than
left as a modifier that does nothing; and `accessibilityElement(children: .combine)` came off the port stepper's label
because a stepper already synthesizes the adjustable element VoiceOver increments.

**CI-verified: no — the first run failed, and the failure was a real one.** Run
[44660409341](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/44660409341) on `3b64b00` died in *Build + test on
simulator* with one compiler error: `SettingsView+Tools.swift:18:33: function declares an opaque return type, but has no
return statements in its body from which to infer an underlying type`. The cause is a rule this machine cannot exercise:
`var body: some View` gets its result builder from the `View` protocol requirement, and a hand-written
`var toolsSection: some View` in an extension gets none — so the moment my change put a second `Section` beside the first,
the body stopped being one expression and stopped compiling. `@ViewBuilder` on that property is the fix. Because the error
class is invisible to `swiftc -parse`, `Scripts/check-viewbuilder.sh` now reports any computed property or helper whose body
holds two top-level views with no `@ViewBuilder`; it is wired into `Scripts/ci.sh guards` and into the guard job in
`.github/workflows/ci.yml`, so the next one is caught in seconds on Linux rather than six minutes into a macOS build. A
review pass on the same code proposed wrapping every `.textInputAutocapitalization` / `.keyboardType` call in `#if os(iOS)`
because those modifiers are unavailable on macOS; that finding is **rejected against evidence** — the identical calls were
in `WebSearchProviderEditor.swift` at `e203fca` and were green in run 44652196582, `CairnAppUI` is compiled for the iOS
simulator only, and no host-test lane builds it for macOS. **On-device-verified: no.** **Real-network-verified: no.** A
green run for this pass is still owed, and nothing here is claimed as a milestone until one exists.

**CI-verified: yes — run [44663240675](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/44663240675) on `d7837ec`,
completed success.** Privacy guards green with the new `check-viewbuilder.sh` step in the guard job and the guard self-test
still at 53/53; Host unit tests on macOS — **585 domain + 170 remote, 0 failures**; Build + test on iPhone 17 / iOS 26.5 —
build green, **195 `CairnTests`, 0 failures**, which is 193 plus the two Web Search filter tests added here: the stricter
Safe Search value and the chosen window come back off the stored row, and a fresh draft still stores no window. The claim is
pinned to `d7837ec` — the run before it, `44660409341` on `3b64b00`, is the one that failed to compile. **On-device-verified:
no** — no popover in this pass has been seen on a screen, which is the standing gap above. **Real-network-verified: no** —
nothing here sends a request.

### The catalogue, not the view, holds the words

`SettingInfoKey` (33 keys across five groups: Settings, Chat, Web Search, Server, Sharing) and `SettingInfo`
(`title` + `detail`) live in `CairnChatDomain`, so the explanation of a knob is a domain fact with the same status as the
knob itself. `SettingInfoTests` holds the copy to account: the key count per group, a floor of 160 characters of detail per
entry, and named claims inside the prose — "Keychain" where a credential is described, "disk" where storage is described,
"badge" where the outbound indicator is described, "recency" where the search window is described. Copy that drifts away
from what the code does fails a test instead of quietly becoming marketing.

### Three primitives, and the rule about where the `(i)` may sit

* `InfoButton` — the glyph and its popover. `.presentationCompactAdaptation(.popover)` sits on the **presented content**
  (`InfoPopoverContent`), not on the presenting button: on iPhone a popover is adapted to a full-screen sheet unless the
  content itself says otherwise, and a sheet covering the screen is a new screen, with the keyboard dismissed and the
  composer gone under it. The whole point of the note is that it stays attached to the control while the control is still
  reachable.
* `InfoRow` — a control plus an optional caption plus the `(i)` as a **sibling below it**, so the tap cannot be swallowed by
  the control it explains.
* `InfoSectionHeader` — the header form, for the rows that cannot carry the button inside them.

That last clause is the rule worth keeping: a `NavigationLink` row and a menu-`Picker` row make the **entire row** the tap
target, so an `(i)` placed in their label is a button inside a button and loses. Those get the header. Toggles, text
fields, steppers and secure fields take `InfoRow`. Where a section used to be disabled as a whole (Share's engine list when
no engine is offered), the `.disabled` moved onto a `Group` inside the section so the header's `(i)` still opens — the note
about what is shared has to be readable precisely when nothing can be changed.

### Wired, and two controls that had no UI at all

`ChatConfigEditor` (+`Persona`, +`Context`), `SettingsView` (+`Theme`, +`Tools`), `WebSearchSettingsScreen`,
`WebSearchProviderEditor` (+`Basics`, split out so the instance-field section keeps its own wiring apart from the
credential section), +`Sections`, `ServerProfileEditor+Sections`, `ServerProfileRow`, `ShareView` (+`Selection`),
`ToolSwitchMenu`, `ChatScreen+Menus`. Two of the 33 keys described knobs the app could not actually set: **Safe Search** and
the search **window** (`Only From`). Both now have controls, both persist through `WebSearchSettingsModel.save`, and
`Tests/CairnTests/WebSearchSettingsModelTests.swift` gained the two tests that prove it — a saved row carries the stricter
filter and the window it was given, and a fresh draft keeps the middle filter and **no window at all**, because a default
recency window answers a question nobody asked. `WebSearchTimeRange` is honest about its limits in the domain comment and in
the card: DuckDuckGo's endpoint has no such parameter, so that route drops the value instead of inventing a substitute.

### Known gaps

* No test hosts a popover, so nothing proves on a screen that the card floats rather than sheets. `CairnAppUI` has no test
  target and `Tests/CairnTests` is logic-and-wiring only; the copy itself is asserted in the domain, which is where it is
  defined. A view test would need a new pattern in that suite — deliberately deferred rather than guessed at from a machine
  that cannot run it.
* The card's height bounds (`minimumHeight` 90, `maximumHeight` 380) are declared, not measured; only a screen can show
  whether a long card at a large text size scrolls instead of clipping.
* On iPad and Mac the popover is already a popover, so the adaptation clause changes nothing there — asserted by reading
  Apple's documented behaviour, not by running the iPad build.
* `InfoSectionHeader` in a `Section` header has not been seen on a device: a control inside a header view is exactly the
  kind of container SwiftUI has opinions about.
## 2026-11-19 — the Download Models catalog: a list to choose from, and one permission that covers both kinds of download

The Model Manager's Download tab was a text field. Everything else in the app lets a person pick from a list; this one
made them type `mlx-community/…` or `qwen3:8b` from memory. The curated catalog already existed in the domain
(`DefaultModelCatalog`, eight entries with published sizes) and nothing on screen used it.

### What landed

`ModelCatalogScreen` replaces `ModelDownloadForm` in both tabs. A segmented **Install onto** picks the destination — this
phone, or the connected server — and the screen then lists either the curated on-device catalog filtered by what is
actually available in the runtime, or the tags a running server will accept, each row carrying the pull command it will
run. Capability chips filter the list, size and name order it, and tapping a card opens `ModelDetailSheet` with the
published facts and one primary action. The free-text form is still reachable where it is the only option: a server that
offers no tags, and any Ollama-compatible server when adding by name.

`ModelCatalogModel` is the whole view model; the App injects a `LocalModelLibraryServicing` (a listing plus a download
stream) because `CairnAppUI` may open neither URLSession nor `CairnInferenceLocal`. `App/OnDeviceModelLibrary.swift`
bridges the two: it reads installed models from the on-disk manifests rather than trusting an in-memory list that is empty
before an engine is created, and its `download` runs `ModelDownloadManager` behind a `LocalTransferState` stream.
`CairnApp.swift` builds both at launch so a download works before any engine exists.

`ModelTransferStatus` is the one progress shape both paths report through. The on-device path states
queued/downloading/verifying/installed and a byte total from the file listing; the server path reports the server's own
status text and a total only when the server names one, and says "total size not stated" when it does not. No invented
stage, no 0% bar.

### The two decisions worth their cost

**Showing the list and moving the weights are different permissions.** `showsDownloadCatalog` defaults on: a list of names
asks nothing of the network and does not need a switch. `modelDownloadsAllowed` defaults off: gigabytes leaving the device
is the permission, and it is the *same* switch that lets a pull run against a user's own Ollama server, because a pull
fetches weights from somewhere else too. It is badged `.publicInternet`, and Settings carries both the catalog switch (in
the Model section) and the download switch (in Network & Privacy, beside Web Search and LAN sharing).

**The grant is read, never copied.** The model holds a `ModelTrafficSwitch` — two `@MainActor` closures over the live
`ThemeModel` — and consults it at tap time. A `Bool` captured at launch would let a download start after the user had
revoked traffic ten seconds earlier; the test that pins this is `testRevokingTheGrantStopsTheNextDownload`.



### Verification — the three tiers, not merged

* **Host:** `swift test` green in `CairnChatDomain` — new `ModelTransferStatusTests`, the unstated-size-sorts-last rule in
  both directions, the two new `(i)` keys (35 total), the settings defaults and the legacy-nil round-trip.
  `bash Scripts/parse-check.sh` parses 642 files clean; `Scripts/ci.sh guards` reports 53 ok / 0 failed.
* **CI-verified:** *pending on this push.* The `Tests/CairnTests` cases added here — the catalog asks nothing, the phone
  path reaches the library only after the switch, the server path asks the connected server, no server means no offer,
  cancel stops the task, revoking stops the next download — have never run: that target compiles only under `xcodebuild`,
  and this machine has no Xcode. The App bridge (`OnDeviceModelLibrary`, its download half, and the `CairnApp` wiring) is
  likewise uncompiled here; a strict-concurrency review caught two capture errors before the push (`var` captured by a
  `@Sendable` progress closure; a `@MainActor` test stub reached through `self` inside a `@Sendable` stream builder).
* **On-device / real-network:** pending. Nothing on this list has been seen on an iPhone or against a live server.

### Device checklist for this screen — six lines, each says what it proves

1. Servers → On-Device → **Download models** opens the curated list with sizes matching `DefaultModelCatalog`. Proves the
   App's bridge into `CairnInferenceLocal` is wired, not merely compilable.
2. Flip to **This server** with nothing connected: the screen says connect first and offers nothing to tap. Proves the
   inert state instead of a list of taps that would fail.
3. With a live Ollama server the tag list appears; a row already installed opens a sheet whose primary action is
   **Use in this chat** and whose footer states the bytes were already fetched. Proves installed rows are marked, not
   duplicated.
4. Turn **Model Downloads** off and tap a row: a notice names the Settings toggle and no socket opens. Turn it on and tap
   again: the transfer starts. Proves the grant is read at tap time.
5. Start a phone download: bytes count up, a listing that states no size reads "total size not stated" with no bar, and
   **Cancel** leaves a resumable partial. Proves resume and the honest-fraction rule.
6. Start a server pull, then open Settings → Network & Privacy: **Model Downloads** is the row that reads allowed, and its
   `(i)` says the same switch covers both paths. Proves one permission governs both kinds of download.

### Known gaps

* No automated test hosts the screen — `CairnAppUI` has no test target. The sheet's states, the chip bar and the segmented
  destination are asserted only through the view model.
* A server's tag list is the *offer* the backend makes; whether a pull of a listed tag succeeds stays the server's
  business, and no stub can promise it.
* Ollama frequently reports no total for a pull while an OpenAI-compatible server may report one. Both shapes are handled;
  neither has been observed.

