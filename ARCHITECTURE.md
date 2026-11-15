# ARCHITECTURE — Cairn

Local-first native iOS client for running LLM chats against on-device models, your own
LAN servers, and (only when you opt in) the public internet. Original clean-room design:
no code, assets, branding, or UI copied from Off Grid AI, Reins, or any other client.

## 1. Build facts (verified, not assumed)

| Item | Value |
|---|---|
| Authoring machine | Windows 11 — **no Xcode, no `xcrun`, no `xcodegen`, no Swift toolchain** |
| Build box | GitHub Actions `macos-26` (macOS 26.7.2, arm64), **Xcode 26.6 default** |
| SDK ceiling on that runner | **iOS 26.5** (`iphoneos26.5`, `iphonesimulator26.5`) — there is no iOS 27 SDK on `macos-26` |
| Simulator pinned for tests | **iPhone 17 / iOS 26.5** |
| XcodeGen | **not preinstalled** → installed in CI with `brew install xcodegen` |
| Preview lane | `xcode-27` image (public preview) runs the **nightly** job only |
| App deployment target | **iOS 26.0** (`IPHONEOS_DEPLOYMENT_TARGET` in `project.yml`) |
| Package platform floors | iOS 18 / macOS 14 — lower floors keep `Package.swift` parseable across toolchains and let `#available(iOS 26.*)` gates do the work; the shipped minimum is still 26.0 |
| CI cost | Standard macOS runners are **free on public repositories**; private repos bill macOS at $0.062/min |
| Distribution | unsigned device IPA via `ipa.yml` (workflow_dispatch) → Sideloadly + free Apple ID (7-day expiry, ≤3 apps/device); see ROADMAP **Decisions** and `docs/INSTALL.md` |

## 2. Module graph

```
Cairn (app target, iOS 26.0, generated from project.yml)
 ├─ CairnAppUI        SwiftUI views + Cairn identity. No networking, no SwiftData.
 ├─ CairnChatDomain   Swift 6 strict, pure. Chat tree, session, streaming state,
 │                    providers protocol, ChatWorkspace, MockStreamingProvider.
 ├─ CairnPersistence  Swift 6 strict. SwiftData records + SwiftDataStore.
 └─ (M2) CairnProviderRemote   URLSession, SSE, Keychain profiles
                               (Bonjour discovery deferred to M7: the zero-ATS-exception
                               policy makes plaintext LAN servers unreachable anyway)
    (M3) CairnInferenceLocal   Foundation Models, memory budget, model downloads
    (M3) CairnInferenceNative  Swift 5 MODE ONLY — llama.cpp / mlx-swift C++ interop
                               is not strict-concurrency-clean; isolated and actor-wrapped
```

Dependency direction is one-way: `CairnAppUI → CairnChatDomain ← CairnPersistence`.
Nothing imports `CairnAppUI`. SwiftPM is used for module boundaries only; the app target
in the generated `.xcodeproj` is the product.

## 3. Chat is a tree, from Milestone 1

```
Conversation { id, title, activeLeafID, mode, params, createdAt, updatedAt }
ChatNode     { id, conversationID, parentID?, role, kind, text, thinking?,
               state, branchIndex, providerID?, modelID?, createdAt,
               drafts: [CandidateDraft], metrics? }
```

- Visibility is decided **only** by `activeLeafID`. `ChatTree.path(fromRootToLeaf:)`
  walks parent pointers with a visited-set guard against malformed cycles.
- `edit` and `regenerate` **append a sibling** under the same parent with
  `branchIndex = max(siblings) + 1`. History is never rewritten, never deleted, and
  never renumbered, so `< 1 / N >` is stable and old branches stay walkable.
- A **Hybrid Synthesized** turn is ONE `kind == .synthesized` assistant node carrying
  `drafts[]` (device draft, remote draft, agreements/disagreements/unsupported claims,
  unified answer). It replays, exports, and imports as a single node.
- On disk, a node is a row keyed by `id` with `parentID` + `branchIndex`. Streaming
  updates are `UPDATE one row`, never an array rewrite.

## 4. Providers

```swift
enum StreamChunk { thinking(String) | content(String) | toolCall(ToolCallRequest)
                                      | metrics(GenerationMetrics) }

protocol InferenceProvider: Sendable, Identifiable {
  var networkClass: NetworkClass { get }        // .onDevice .privateLan .tailnet .publicInternet
  var capabilities: ProviderCapabilities { get } // streaming/thinking/tools/vision/pull/delete/ps
  func models() async throws -> [ModelInfo]
  func stream(_ request: GenerationRequest) -> AsyncThrowingStream<StreamChunk, any Error>
}
```

- **Reasoning panels appear only when a backend really emits `.thinking`** (a thinking
  field or `<think>` tags). Nothing in the UI may synthesize, paraphrase, or guess
  reasoning. `StreamAccumulator.hasReasoning` is the single gate, and the row renderer
  reads `node.thinking`, which is nil unless a thinking chunk arrived.
- Every capability-derived control in the UI comes from `ProviderCapabilities`, so an
  OpenAI-compatible server never shows Pull / Delete / Loaded-models buttons that its
  API cannot serve.

## 5. Streaming + cancellation

`ChatSessionModel` drains the provider stream, reduces chunks into a
`StreamAccumulator` (a value type, so a whole turn's state is snapshot-able and
testable), and **persists the partial turn on every chunk**. Cancel flips the phase to
`.cancelling`, cancels the drain `Task`, and the `CancellationError` path persists the
partial text with state `.cancelled`. A mid-stream provider error keeps the partial
text and marks `.failed`; `interrupted` is reserved for Milestone 5 background recovery.

> **Finding from the first CI run (M1):** cancelling a `Task` that is suspended inside
> `for try await` over an `AsyncThrowingStream` does **not** reliably throw — the stream
> can end the iteration cleanly. Draining code must therefore check `Task.isCancelled`
> (or the `.cancelling` phase) *after* the loop before declaring a turn `.complete`,
> otherwise a truncated answer is reported as a finished one. The test
> `testCancellationKeepsPartialTextAndMarksNodeCancelled` pins this.

The same run exposed an API footgun: the pure `ChatTree` functions are value-in /
value-out, so `let node = append(...).node` silently discards the returned array and
leaves parents missing from the tree. `ChatDraftTree` wraps those functions, keeps the
array on every mutation, and returns `@discardableResult` nodes — use it for fixtures,
import (M5), and any code that builds a tree incrementally.


## 6. Temporary chat is a store choice, not a UI flag

`ChatWorkspace` owns two stores: `SwiftDataStore` (disk) and `EphemeralStore` (memory).
Toggling Temporary Chat **starts a new chat bound to the other store** — history is
never copied between stores, so an ephemeral conversation has no code path to disk, and
`SwiftDataStore` additionally **throws** if handed a conversation marked temporary.

## 7. Privacy model (enforced, not documented)

- History, settings, attachments: on-device only. No iCloud, no analytics, no accounts.
- Secrets: Keychain only, `.afterFirstUnlockThisDeviceOnly`. Never UserDefaults, never a
  plist, never a CI log, never an issue body.
- **Logging:** `Scripts/check-logging.sh` fails CI on `print(`, `NSLog(`, `debugPrint(`,
  `os_log(`, `fatalError(` in production sources. Log typed metadata only: UUIDs, enums,
  counts, byte sizes, durations.
- **Network class is a first-class value.** Every request is tagged `.onDevice`,
  `.privateLan`, `.tailnet`, or `.publicInternet`, and the header shows a `NetworkBadge`
  for the active provider. `.publicInternet` requires explicit opt-in before the first
  request and keeps a persistent badge afterwards (web search, Ollama Cloud).

### ATS / Local Network matrix (Milestone 2 design, already encoded in the guard)

| Situation | Mechanism | Notes |
|---|---|---|
| LAN over RFC 1918 / `.local` / unqualified host, plaintext | not adopted | `NSAllowsLocalNetworking` is itself an ATS key, and the zero-exception policy forbids any ATS key in any configuration; plaintext LAN HTTP is unsupported — run `tailscale serve` on the server instead |
| Tailscale `100.64.0.0/10` | **Not** covered by `NSAllowsLocalNetworking` (and we add no ATS keys) | Use MagicDNS HTTPS via `tailscale serve --bg --https=443 <port>` |
| Tailscale with TLS | `tailscale serve` → `https://<device>.<tailnet>.ts.net` | `serve` auto-provisions and auto-renews **Let's Encrypt** certificates — trusted by iOS by default; **no ATS exception, no custom CA** — the only supported remote route |
| Plaintext anything (LAN HTTP, Tailscale HTTP) | none | ATS blocks it and no configuration adds exceptions; the profile editor rejects HTTP URLs with an explanatory error pointing at `tailscale serve` |
| LAN IP literal over HTTP | Impossible via exceptions | `NSExceptionDomains` cannot match IP literals |
| Anything | `NSAllowsArbitraryLoads` | Banned: it is ignored when `NSAllowsLocalNetworking` is present, and it is a blanket exception. `Scripts/check-ats.sh` fails on it |

The shipped `App/Info.plist` contains **no** `NSAppTransportSecurity` key, and **no
configuration adds one later** (decision 2026-11-14: remote access is HTTPS-only via
`tailscale serve`; this supersedes the earlier Debug-only split-plist plan). The real
MagicDNS hostname never enters the repository: docs and tests use the placeholder
`your-host.your-tailnet.ts.net`, and `Scripts/check-hostname.sh` enforces that in CI.

## 8. Memory guardrails (Milestone 3)

`os_proc_available_memory()` is a **point-in-time headroom estimate**, not a budget for
a whole session. Sizing is conservative: `model bytes + KV cache bytes`, where KV cache
scales with `2 × layers × kv_heads × head_dim × bytes_per_element × context_length`,
computed for the **active** context length rather than the model maximum. Load failures
and `UIApplication` memory warnings degrade to a smaller context or a smaller model with
a visible reason instead of a crash. The increased-memory-limit entitlement is treated
as optional uplift: Milestone 3 is validated **without** it first, then re-tested with it
if the signing profile grants it. **Hard rule:** never two on-device models resident
unless headroom says yes.

## 9. Background policy (Milestone 5)

`BGContinuedProcessingTask` exposes a `.gpu` resource on iOS/iPadOS 26+, but per Apple
DTS only iPads with M3 or newer support it and no iPhones do. So: check
`BGTaskScheduler.shared.supportedResources` at runtime and assume it is absent on
iPhone. On-device generation **pauses on backgrounding** and resumes through Continue;
remote user-initiated streams may use `BGContinuedProcessingTask` without `.gpu`, with
`beginBackgroundTask` as fallback. Partial output is already persisted incrementally
(§5), so recovery is a re-attach, not a replay. ActivityKit is a progress display only —
never a compute strategy.

## 10. Hybrid engine (Milestone 4)

Four modes per chat or prompt: On-Device Only, Remote Only, Hybrid Parallel
(`withTaskGroup`, both streams live with independent tok/s), Hybrid Synthesized (both
drafts stream into collapsible panels; a user-selected synthesizer lists agreements,
disagreements, and unsupported claims, then writes one unified answer stored as a single
synthesized node). The synthesizer defaults to the remote model, or runs sequentially
when only a device model is available — never a second resident device model.

## 11. Testing strategy

| Layer | Where | What |
|---|---|---|
| Pure tree algebra | `swift test` (macOS host, cheap) | branch indexes, edit/regenerate as siblings, `<1/N>`, cycle guard, synthesized node, message flattening |
| Streaming state | same | phase transitions, thinking-gating, cancel keeps partial text, metrics never invented |
| Session behaviour | same, against `MockStreamingProvider` | send/cancel/fail/regenerate/stepper, temp chat stays in memory |
| SwiftData | `xcodebuild test`, iPhone 17 / iOS 26.5 | parent-pointer round trip, one-row streaming updates, refused temporary writes, params/drafts/thinking persistence |
| Real engines, Bonjour, Local Network prompt, Metal GPU, memory headroom | **physical iPhone only** | CI has no LAN, no local-network permission flow, no iPhone memory limits |

## 12. Open decisions

- App icon PNG pipeline (the mark is currently drawn in code as `CairnMark`).
- On-device primary backend: Foundation Models as the guaranteed iOS 26 path, with
  llama.cpp vs mlx-swift evaluated in Milestone 3 for models Apple's API cannot serve.
- ~~Per-configuration ATS plist split~~ — superseded 2026-11-14 by the zero-ATS-exception
  decision (ROADMAP **Decisions**): remote is HTTPS-only via `tailscale serve`.
- Paid Apple Developer Program: revisit only after M3's on-device checklist; the
  free-Apple-ID sideload path is documented in `docs/INSTALL.md`.
- Bundle id `app.cairn.cairn` — change it if your team prefix differs.

## 13. Distribution & signing (verified 2026-11-14)

- CI `ipa.yml` (workflow_dispatch only): Release build for `generic/platform=iOS` with
  `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`, then
  `Payload/Cairn.app` is zipped into `Cairn-unsigned.ipa` and uploaded as an artifact.
  The job asserts: arm64 binary, parseable Info.plist, **app is unsigned**.
- Install: Windows PC + Sideloadly (v0.71+) + free Apple ID. Free-account limits: 7-day
  expiry (auto-refresh daemon re-signs near expiry), ≤3 active sideloaded apps per
  device, ~10 App IDs/year. Downloading a workflow artifact needs a signed-in GitHub
  account even for a public repo. Full steps in `docs/INSTALL.md`.
- Free-Apple-ID signing carries **no custom entitlements** (Sideloadly's entitlements
  feature is Apple Developer Program only), so Cairn never requires
  `com.apple.developer.kernel.increased-memory-limit`. `Entitlements/Cairn.entitlements`
  (release-clean, empty) and `Entitlements/Cairn-sideload-experiment.entitlements`
  (memory-limit experiment) exist for the later paid/Xcode signing path only.

