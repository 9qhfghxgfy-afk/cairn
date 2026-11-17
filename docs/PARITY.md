# PARITY — Cairn feature ledger

Functional-parity ledger: what the Reins-class client set does, which Cairn milestone owns each
piece, and how far verification actually got. Scope memory only — no third-party app's text, art,
or branding is recorded here (clean-room per `PRD.md` and `.clinerules`).

Status: `Done` · `Partial` · `Missing` · `Conflicts`.
Verification: `CI-verified` · `on-device-verified` · `real-network-verified` · `local-Mac-verified` · `unverified`.

Rule: a row becomes `Done` only in a commit citing a green CI run, and never loses its
verification label. `CI-verified` is not `on-device-verified`.

## 0. Ledger — chat UX (3.1)

| Feature | Spec | Milestone | Status | Verification |
|---|---|---|---|---|
| Chat tree, `< 1 / N >` branch navigation | 3.1 | M1 | Done | CI-verified (`43685125186`) |
| Edit / regenerate append a sibling, never rewrite | 3.1 | M1 | Done | CI-verified |
| Stop mid-stream keeps partial text, marks `.cancelled` | 3.1 | M1 | Done | CI-verified |
| Temporary chat is memory-only; disk store refuses it | 3.1 | M1 | Done | CI-verified |
| Reasoning panel gated on real thinking only | 3.1 | M1 | Done | CI-verified |
| Generation stats (tok, tok/s) on a reply | 3.1 | P2 | Partial — always shown, no toggle, no elapsed | CI-verified |
| Remote streaming with real usage metrics | 3.1 | M2 | Done | CI-verified (`43764696840`); device list open |
| Chat-history sidebar / drawer with chat list | 3.1 | M5 | Missing | unverified |
| Editable chat title in the top bar | 3.1 | M5 | Missing | unverified |
| Quick server/model switcher in the top bar | 3.1 | P1 | Partial — model menu only | unverified |
| Empty state that routes to "configure a server" | 3.1 | P1 | Partial — static, no action | unverified |
| Composer `+` menu (Photos, Camera, Files) | 3.1, 3.8 | M6 | Missing | unverified |
| `Thinking` / `Tools` composer chips | 3.1, 3.2 | P2 · P3 | Missing | unverified |
| Markdown + syntax-highlighted code + copy button | 3.1 | M5 | Missing (plain `Text`) | unverified |
| Continue Generation after a cut-off reply | 3.1 | M5 | Missing (`interrupted` reserved) | unverified |
| Duplicate chat up to the current branch | 3.1 | M5 | Missing | unverified |
| Temporary-chat banner + "keep a copy" | 3.1 | M5 | Missing (toggle only) | unverified |
| Chat list search / rename / duplicate / delete, no caps | 3.1 | M5 | Partial — delete + select only | unverified |

## 0b. Ledger — per-chat config (3.2) and injected context (3.3)

| Feature | Spec | Milestone | Status | Verification |
|---|---|---|---|---|
| Persona / system-prompt editor | 3.2 | P2 | Partial — field exists, no editor | CI-verified (field) |
| Context size 2K→256K snap (default 8K) | 3.2 | P2 | Partial — default 4096, no control | unverified |
| Temperature 0.00–2.00 (default 0.80) + numeric | 3.2 | P2 | Partial — default 0.7, no control | unverified |
| Seed random/fixed + randomize | 3.2 | P2 | Missing | unverified |
| Top P 0.90 · Min P 0.00 · Top K 40 | 3.2 | P2 | Partial — `topP` 0.95 only | unverified |
| Max Tokens unlimited vs limited | 3.2 | P2 | Partial — fixed 1024 | unverified |
| Repeat Penalty 1.10 · Repeat Last N 64 | 3.2 | P2 | Partial — penalty only | unverified |
| `configured` vs `use default` (muted + omitted from payload) | 3.2 | P2 | Missing — knobs always send | unverified |
| Reset to Defaults + per-parameter `(i)` | 3.2 | P2 | Missing | unverified |
| Backend capability filter for sampling keys | 3.2 | P2 | Missing | unverified |
| Default Configuration + "N options configured" badge | 3.2 | P2 | Missing — no Settings screen | unverified |
| Live monospace assembled-context preview | 3.3 | P2 | Missing | unverified |
| Always-injected toggles (date / time+tz / platform / language) | 3.3 | P2 | Missing | unverified |
| 3 added injections (region, capability summary, format pref) | 3.3 | P2 | Missing — see §2 | unverified |
| Conditional injections (tools / force fetch / file / image) | 3.3 | P2 → P3, M6 | Missing | unverified |

## 0c. Ledger — servers (3.4) and model management (3.5)

| Feature | Spec | Milestone | Status | Verification |
|---|---|---|---|---|
| Server list with unlimited profiles | 3.4 | M2 | Done | CI-verified (`43771679253`) |
| Add/Edit server: name, address, kind, token, headers | 3.4 | M2 | Done | CI-verified |
| Credential headers refused in plain storage | 3.4 | M2 | Done | CI-verified |
| Plaintext + outbound badges, class derived from URL | 3.4 | M2 | Done | CI-verified |
| Instant one-tap switching + per-server last model | 3.4 | P1 | Missing | unverified |
| Status dot + Connect/test action | 3.4 | P1 | Partial — tester exists, no dot | CI-verified (tester) |
| Selector: Ollama / LM Studio / OpenAI-compatible | 3.4 | P1 | Partial — 2 kinds; LM Studio folded into OpenAI | CI-verified (2 kinds) |
| Ollama Cloud profile (off by default, badged) | 3.4, 3.7 | P1 | Missing | unverified |
| "How do I get started?" guide sheet | 3.4 | P1 | Missing | unverified |
| Scan Local Network, bounded, prefills Add Server | 3.4 | P1 | Missing | unverified |
| Local Network prompt + denial handling | 3.4 | M2 | Partial — hint only, unproven on device | real-network pending |
| On-Device row pinned at top with runtime status | 3.4, 3.5 | M3 | Missing | unverified |
| Running / Installed / Download model manager | 3.5 | M3 | Partial — service exists, no tabs/progress | CI-verified (service) |
| Streaming pull progress + cancel | 3.5 | M3 | Missing — silent drain | unverified |
| Model detail via `/api/show` | 3.5 | M3 | Partial — `/api/tags` only | CI-verified |
| Unload / evict a loaded model | 3.5 | M3 | Missing | unverified |
| LM Studio native lifecycle (`/api/v1/*`) | 3.5 | M3 | Missing — Finding F2 | unverified |
| OpenAI-compatible: info copy instead of lifecycle | 3.5 | M3 | Partial — gated, no copy | CI-verified |
| On-device catalog (mlx-community + any HF MLX id) | 3.5 | M3 | Missing | unverified |
| Footprint estimate vs `os_proc_available_memory()` + warning | 3.5 | M3 | Missing | unverified |
| Background downloads: progress, cancel, resume, SHA-256 | 3.5 | M3 | Missing | unverified |
| MLX runtime (`mlx-swift-lm`) in an isolated Swift 5 module | 3.5 | M3 | Missing — Finding F3 | unverified |
| Apple Foundation Models behind `#available` + availability | 3.5 | M3 | Missing — Finding F5 | unverified |
| `<think>` + tool-call parsing for on-device templates | 3.5 | M3 | Missing | unverified |
| Memory-pressure safeguards, never two resident models | 3.5 | M3 | Missing | unverified |

## 0d. Ledger — sharing, tools, attachments, backup, polish (3.6–3.11)

| Feature | Spec | Milestone | Status | Verification |
|---|---|---|---|---|
| LAN model-sharing server (Ollama + OpenAI, SSE/NDJSON) | 3.6 | P4 | Missing | unverified |
| Sharing off by default, per-session opt-in, Keychain token | 3.6 | P4 | Missing | unverified |
| Sharing status: IP, port, client count, persistent badge | 3.6 | P4 | Missing | unverified |
| LAN bind only; documented background-suspension limits | 3.6 | P4 | Missing | unverified |
| `ToolRegistry` loop + step limit + cancel + call cards | 3.7 | P3 | Partial — `.toolCall` chunk only | CI-verified (chunk) |
| Native tool calling + documented prompt-protocol fallback | 3.7 | P3 | Missing | unverified |
| web_search, web_fetch, wiki_search, calculator, compose_mail | 3.7 | P3 | Missing | unverified |
| Keyless default search + optional SearXNG URL | 3.7 | P3 | Missing — Finding F4 | unverified |
| Ollama Cloud search route when that profile is active | 3.7 | P3 | Missing — Finding F4 | unverified |
| Tools off by default, per-chat opt-in, badge, disclosure | 3.7 | P3 | Missing | unverified |
| Send only the query/URL, never conversation history | 3.7 | P3 | Missing | unverified |
| File attachments: PDF/CSV/TXT/MD/code + size check | 3.8 | M6 | Missing | unverified |
| Full-text vs chunk-retrieve by context budget + citations | 3.8 | M6 | Missing | unverified |
| Image attachments, downscale, multimodal payloads | 3.8 | M6 | Partial — `imageData` field only | CI-verified (field) |
| Vision badge + warn on a non-vision model | 3.8 | M6 | Partial — flag derived, no warning | CI-verified (flag) |
| Export one chat / all chats: `.cairn` JSON or Markdown | 3.9 | M5 | Missing | unverified |
| Import `.cairn` with version check + duplicate-ID handling | 3.9 | M5 | Missing | unverified |
| Themes: original palettes, swatches, live bubble preview | 3.10 | P2 | Missing — one hard-coded theme | unverified |
| Background Processing toggle (`BGContinuedProcessingTask`) | 3.10 | M5 | Missing | unverified |
| Generation Statistics toggle | 3.10 | P2 | Missing | unverified |
| Privacy statement, issues link, licenses view | 3.10 | P5 | Missing | unverified |
| Dynamic Type, VoiceOver, Reduce Motion | 3.10 | P5 | Partial — a few labels | unverified |
| AppIcon asset pipeline | 3.10 | P5 | Missing — mark drawn in code | unverified |
| Hybrid engine preserved (schema now, engine in M4) | 3.11 | M4 | Partial — schema + modes stored, engine absent | CI-verified (schema) |
| Keychain secrets, network class, privacy guards kept | 3.11 | M0–M2 | Done | CI-verified |
| Zero paywall, zero limits, guard-enforced | §0 | P0 | **Done** — `Scripts/check-no-paywall.sh`, wired into `ci.sh guards` and the CI guards job | local-Mac-verified (self-test 53 ok / 0 failed); CI pending |
| No in-app billing, no tracking hook anywhere | §0 | P0 | **Done** — none present, and now machine-enforced | local-Mac-verified; CI pending |

## 1. Findings that change the spec (verified 2026-11-16)

- **F1 — the local lane cannot run the pinned destination.** `Scripts/ci.sh probe` on this Mac:
  Xcode 27.2 (27B52), iOS 27.2 SDKs, iOS 27.2 simulator runtimes only. No iOS 26.5 runtime, so
  `ci.sh test` falls back to a name-only destination. The Xcode license is now accepted, which
  supersedes the 2026-11-16 Mac record. Per `.clinerules` the pin is recorded, not bumped: CI stays
  Xcode 26.6 / iPhone 17 / iOS 26.5, local runs 27.2, and anything newer than the 26.5 SDK must be
  gated with `#available` / `canImport` rather than assumed.
- **F2 — LM Studio is no longer OpenAI-only.** LM Studio 0.4.0 shipped a native v1 REST API:
  `GET /api/v1/models`, `POST /api/v1/models/load`, `POST /api/v1/models/unload`,
  `POST /api/v1/models/download`, `GET /api/v1/models/download/status`, `POST /api/v1/chat`, with
  optional API-token auth, next to the OpenAI-compatible `/v1/*`. Lifecycle exists, so
  `ServerProfileKind` gains an `lmStudio` case with pull/load/unload enabled. The legacy v0 API must
  not be assumed.
- **F3 — MLX Swift LM moved repositories.** `MLXLMCommon`, `MLXLLM`, `MLXVLM`, `MLXEmbedders` moved
  from `mlx-swift-examples` to **`ml-explore/mlx-swift-lm`**. Pin against that repo. Its Hugging Face
  downloader is not a background `URLSession` client, so Cairn owns download, resume and SHA-256 and
  hands MLX a local directory.
- **F4 — Ollama web search is not automatic.** It is its own endpoint,
  `POST https://ollama.com/api/web_search` (`query`, optional `max_results`; returns
  `results[].title|url|content`) and **requires an API key plus a free Ollama account**. The spec's
  "cloud models search automatically with no key" is not achievable as written. Proposed: the keyless
  provider is the default for every local and standard server; the Ollama Cloud route becomes a
  key-gated provider that only turns on when the user supplies an Ollama Cloud key. Needs approval.
- **F5 — Apple Foundation Models are system-managed.** Nothing is downloaded through that path, so
  "Download more on-device models" is MLX-only. Availability is read at runtime behind
  `canImport(FoundationModels)` + `#available`, and the exact unstructured-output call shape is
  confirmed against the 26.x SDK at build time, not assumed.
- **F6 — 8 GB is the ceiling.** M1 Mac with 8 GB, iPhone 15 Pro as the target, and no
  `increased-memory-limit` entitlement on free signing. Only small quantized MLX builds are plausible
  on the phone, so the catalog is filtered by measured headroom.

## 2. Proposed additions to the 3.3 injection list (privacy-safe, non-identifying)

1. **Locale region** — the region code only, never a display name or contact.
2. **Active capability summary** — backend plus the capability set on for this turn (thinking, tools,
   vision, context size), so the model stops claiming abilities it does not have.
3. **Response formatting preference** — the chosen answer shape (plain / Markdown / terse), never the
   content of an answer.

## 3. Milestone plan

Order is fixed by dependency: guards/tooling first, then servers, then on-device, then the engine
that needs both. `P*` rows are parity work folded into the existing `M3`–`M7` spine in `ROADMAP.md`;
`M*` rows keep their meaning from `ROADMAP.md` and `ARCHITECTURE.md`.

| # | Scope | Spec | Key files touched | Exit condition |
|---|---|---|---|---|
| **P0** | `Scripts/check-no-paywall.sh` + `ci.sh` guards + `ci.yml` guards job + negative self-test in `test-guards.sh`; local runtime resolution in `ci.sh` recorded as divergence; `docs/PARITY.md` + this ledger committed | §0, F1 | `Scripts/check-no-paywall.sh` (new), `Scripts/ci.sh`, `Scripts/test-guards.sh`, `.github/workflows/ci.yml`, `ROADMAP.md` | guards green locally **and** on CI; self-test proves the guard rejects a planted `import StoreKit` and a planted upsell string without echoing it |
| **P1** | Multi-server management: active-server selection, instant switching with per-server last model, status dot, `lmStudio` + `ollamaCloud` kinds with capability maps, setup-guide sheet, empty-state route, user-initiated LAN scan | 3.4 | `Remote/ServerProfileKind.swift`, `Remote/ServerProfileValidation.swift`, new `Remote/BackendCapabilities.swift`, new `Remote/LANDiscovery.swift` (in `CairnProviderRemote`), `ServersModel.swift`, `ServersView.swift`, `ServerProfileRow.swift`, `ServerProfileEditor+.swift`, new `ServersGuide.swift`, `Persistence/ProfileRecord.swift` | unit tests for kind→capabilities and discovery address classification using only allow-listed example addresses; CI green; **no new ATS key** |
| **M3** | On-device inference: `CairnInferenceNative` (Swift 5, `mlx-swift-lm`) + `CairnInferenceLocal` (Foundation Models, memory budget, downloads), model manager tabs with progress + cancel + unload, `/api/show` details, LM Studio lifecycle, On-Device row | 3.5, 3.4 (row) | `project.yml`, `Packages/CairnInferenceNative` (new), `Packages/CairnInferenceLocal` (new), `RemoteModelService.swift`, `RemoteModelManaging.swift`, new `ModelManagerView+.swift`, `ChatModels.swift` | host unit tests for codec + budget math; CI green; then the iPhone checklist (Metal, memory, resume, SHA-256) |
| **P2** | Per-chat + default configuration with `configured` vs `unset` semantics, capability-filtered payloads, injected-context builder with live preview, themes, statistics + thinking chips | 3.2, 3.3, 3.10 (themes) | `ChatModels.swift` (params → optional overrides), `Persistence/Mapping.swift`, new `ChatDomain/SamplingPayload.swift`, new `ChatDomain/ContextAssembly.swift`, new `CairnAppUI/ChatConfigSheet.swift`, new `CairnAppUI/SettingsView.swift`, `CairnIdentity.swift` (themes) | pure-function tests: unset keys are omitted per backend; defaults propagate to new chats; assembly order is deterministic |
| **M4** | Hybrid Parallel + Synthesized engine, both live, synthesizer as one node carrying drafts | 3.11 | `ChatSessionModel+.swift`, new `HybridEngine.swift`, `StreamAccumulator.swift` | task-group tests with two mocks; synthesized node round-trips export |
| **P3** | Tool runtime + built-ins + search routing (keyless default, SearXNG optional, Ollama Cloud key-gated) | 3.7 | new `CairnChatDomain/ToolRegistry.swift`, `ToolProtocol.swift`, new `CairnProviderRemote/Tools/*.swift`, `ChatSessionModel+Tools.swift`, `MessageRow+ToolCard.swift` | calculator rejects malformed/hostile input with no `NSExpression`; loop honours step limit + cancel; only the query leaves the device (asserted in tests) |
| **M5** | Chat list + sidebar, rename/duplicate/delete/search, Markdown + code copy, Continue Generation, temp-chat banner, background processing, `.cairn` + `.md` export/import | 3.1, 3.9, 3.10 (background) | new `ChatListView.swift`, `ChatDomain/ExportBundle.swift`, `ChatDomain/ImportBundle.swift`, `ChatSessionModel+Continue.swift`, `App/CairnApp.swift` (BG tasks), `MessageRow+Markdown.swift` | export→import round-trip preserves every branch; temp chat writes nothing to disk (store refusal test) |
| **M6** | Attachments: PDF/CSV/text/code with size checks, full-text vs chunked retrieval with citations, images with downscale + vision gating | 3.8 | new `CairnChatDomain/AttachmentModels.swift`, `Chunker.swift`, `Retriever.swift`, new `CairnAppUI/AttachmentMenu.swift`, `ChatMessagePayload` use | chunking + budget choice is pure and unit-tested; a non-vision model cannot send image bytes |
| **P4** | LAN model-sharing server over `NWListener`, Ollama + OpenAI surfaces, per-session opt-in, token in Keychain, LAN-only bind | 3.6 | new `Packages/CairnSharing` (`ShareServer.swift`, `ShareCodec.swift`), `ServersView` sheet, `App/CairnApp.swift` | loopback integration tests in CI for both dialects; on-device proof on the iPhone 15 Pro |
| **P5** | Accessibility pass, AppIcon pipeline, licenses + privacy statement + issues link, doc refresh | 3.10 | `Assets.xcassets` (new), `AppIcon`, new `AboutView.swift`, `README.md`, `docs/*.md` | Dynamic Type at AX sizes; VoiceOver labels on chat/branch/server controls; docs match shipped behaviour |

Deferred pending the user's word: on-device voice in/out (in `ROADMAP.md` M6 but absent from the
parity spec), `.reins` import (no sample provided), and everything currently under M7.

## 4. Open questions carried into the next task

Recorded so the next session does not re-litigate them; answered inline in `ROADMAP.md` once the
user replies.

1. Sequencing vs the open M2 device checklist (10 items, never run on the iPhone).
2. The F4 web-search resolution: keyless default + key-gated Ollama Cloud route.
3. Whether the local test lane runs on the installed iOS 27.2 runtime while CI stays pinned to 26.5.
4. Whether voice stays in M6 or moves to the M7 backlog.
5. Whether the LM Studio `lmStudio` kind is added in P1 (schema) with its lifecycle calls landing in M3.

