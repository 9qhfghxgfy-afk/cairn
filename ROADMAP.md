# ROADMAP — Cairn

Status legend: `done` = green CI run cited · `in-progress` · `todo` · `blocked:<reason>`

Gate for every milestone (from `.clinerules`):
1. `swift test --package-path Packages/CairnChatDomain`
2. `xcodegen generate` → `xcodebuild build` → `xcodebuild test` on iPhone 17 / iOS 26.5
3. `Scripts/check-logging.sh`, `Scripts/check-ats.sh`, and `Scripts/check-hostname.sh` pass
4. `ROADMAP.md` status updated in the same commit, citing the CI run number

| # | Milestone | Status | CI run |
|---|---|---|---|
| 0 | Repo + CI lane | **done** | [43684016580](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/43684016580) — first lane run |
| 1 | Shell + mock streaming loop | **done** — all gates green on `1e7e250` | [43685125186](https://github.com/9qhfghxgfy-afk/cairn/actions/runs/43685125186) |
| 2 | Remote providers | todo | |
| 3 | On-device inference + memory guardrails | todo | |
| 4 | Hybrid Parallel & Synthesized engine | todo | |
| 5 | Advanced controls, interruption recovery, export/import | todo | |
| 6 | Local RAG, vision, web search, voice | todo | |
| 7 | Parity backlog | todo (per-item approval) | |

## Decisions (durable — update here, not in chat)

Recorded 2026-11-14. These supersede anything older in the repo.

- **Distribution / signing.** Free Apple ID (Personal Team). Primary install path: an
  **unsigned device IPA** built by CI (`ipa.yml`, workflow_dispatch only) → signed on
  the Windows authoring PC with **Sideloadly** (v0.71+, Windows builds, iOS 7–27+
  supported) using the free Apple ID. Apple's free-account limits: 7-day signing expiry
  (Sideloadly's auto-refresh daemon re-signs near expiry while the PC can reach the
  device over USB or Wi-Fi), at most 3 sideloaded apps active per device, ~10 App IDs
  created per year. No App Store or TestFlight unless the paid Apple Developer Program
  is joined later; the Release configuration stays App Store-clean either way (zero ATS
  exceptions, no private APIs).
- **Entitlements.** `com.apple.developer.kernel.increased-memory-limit` is treated as
  **unavailable**: free-Apple-ID signing tools cannot attach custom entitlements
  (Sideloadly's custom-entitlement support is Apple Developer Program only; extended
  virtual addressing is paid-only). M3 must work **with and without** the entitlement;
  confirm availability by measuring `os_proc_available_memory()` on the physical device
  in M3 — never trust community reports. The app must never *require* an entitlement.
- **Networking.** Servers are reached over **Tailscale MagicDNS via `tailscale serve`
  HTTPS**. **Zero ATS exceptions in any configuration** — this supersedes the earlier
  plan for a Debug-only scoped `NSExceptionDomains` entry. `serve` auto-provisions and
  auto-renews **Let's Encrypt** certificates for `<device>.<tailnet>.ts.net`; iOS trusts
  them by default, so URLSession needs no custom trust handling and `tailscale cert` is
  not part of the flow. Plaintext HTTP remote profiles are blocked by ATS and get
  rejected at profile-save time with an explanatory error instead of an exception.
  Bonjour discovery of plaintext LAN servers is deferred to M7 (it would only find
  servers ATS refuses to talk to).
- **Hostname policy.** The real MagicDNS hostname must never appear in the repo,
  commits, tests, docs, screenshots, or CI logs. Docs and tests use the placeholder
  `your-host.your-tailnet.ts.net` — the only `*.ts.net` value permitted in tracked
  files (`Scripts/check-hostname.sh` enforces this in CI). The real hostname lives only
  in the app (per-server profile; token in Keychain) or gitignored local config.
- **Test device.** iPhone 15 Pro on **iOS 26.2** (8 GB RAM per Apple's specs — confirm
  on device). Do not assume iOS 27. The CI simulator lane stays iPhone 17 / iOS 26.5.
- **CI lane.** `macos-26` + Xcode 26.6 pinned (SDK ceiling iOS 26.5), deployment target
  iOS 26.0, repo stays **public** (that is what keeps macOS minutes free),
  `actions/checkout@v7` + `actions/upload-artifact@v7` (clears the Node 20 deprecation
  warnings).

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

## Milestone 2 — Remote providers (Ollama, OpenAI-compatible / LM Studio)

- `CairnProviderRemote`: multi-server profiles (name, base URL, custom headers, Keychain
  bearer token), connection tester, model list, Ollama `/api/ps` loaded-models, pull and
  delete where capabilities allow, OpenAI-compatible `/v1/chat/completions` SSE parsing.
- Bonjour discovery for `_http._tcp` plus manual `.local` / LAN-IP entry. Ollama does not
  advertise a Bonjour record by default, so discovery is best-effort and manual entry is
  first-class.
- Local Network permission and `NSBonjourServices` handled independently of ATS; per-config
  plist split so Release has zero ATS exceptions; scoped `NSExceptionDomains` for a
  MagicDNS hostname in Debug only; plaintext-risk badge on any HTTP profile.
- Optional Ollama Cloud profile: off by default, `.publicInternet`, opt-in dialog,
  persistent outbound badge.
- Tests: SSE parser against a localhost stub server in CI — chunk boundaries, `[DONE]`,
  malformed JSON, mid-stream error, cancellation — plus capability gating of server actions.

Acceptance: a real LAN Ollama server streams on the physical iPhone; CI proves the
parsers; the guard proves the Release build carries no ATS exception.

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

Resolved facts (device, signing identity, distribution route, repo visibility) moved to
**Decisions** above. Still open:

- M2 server facts: which engines and versions run on the server machine(s) (Ollama
  version, LM Studio version), which models will be used (thinking-capable or not),
  whether Tailscale is installed on that machine, and whether MagicDNS + HTTPS are
  already enabled on the tailnet.
- `increased-memory-limit` availability: assumed unavailable (see Decisions); confirmed
  only by on-device measurement in M3.
- App-icon asset pipeline (the mark is currently code-drawn `CairnMark`).
