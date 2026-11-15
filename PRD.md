# PRD — Cairn

**Cairn** is a local-first native iOS chat client for running language models on the
device, on servers you own, and — only if you choose it — on the public internet. A cairn
is a stack of stones that marks a trail: the app's mark is a stack of stones, and its
signature feature literally stacks model answers.

## Originality

Clean-room. No code, strings, artwork, iconography, layout, colour identity, or naming
borrowed from Off Grid AI, Reins, or any other client; no decompiling or scraping a
competitor. Only public, documented wire formats are used (Ollama HTTP API,
OpenAI-compatible `/v1/chat/completions`), which is interface compatibility, not copied
expression. The mark is drawn in code (`CairnMark`). The name, icon, and UI must be
re-checked for App Store / trademark collisions before any public release.

## Product invariants

- No subscriptions, paywalls, message caps, telemetry, ads, accounts, or analytics.
- Chat history, settings, and attachments live on the device by default.
- The network is an opt-in peripheral, not a dependency. Anything that leaves the device
  needs explicit opt-in first and keeps a visible badge afterwards.
- The user always knows which machine answered, and at what speed.
- We do not modify, patch, or bypass restrictions in any other app.

## Capabilities

**Chat.** Tree-shaped history: edit, regenerate, and branch without rewriting anything;
`< 1 / N >` branch stepping; continue generation; prompt queueing; search; collapsible
reasoning panels that appear only when a backend really emits reasoning; `.md` and
lossless `.json` (full tree) export/import.

**Engines.** On-device (Foundation Models on iOS 26+; llama.cpp / mlx-swift evaluated for
models Apple's API cannot serve), LAN servers (Ollama including pull/delete/`/api/ps`,
OpenAI-compatible including LM Studio), tailnet endpoints, and an optional Ollama Cloud
profile that is off by default.

**Hybrid engine.** On-Device Only · Remote Only · Hybrid Parallel (both live, side by
side, independent tok/s) · Hybrid Synthesized (both drafts in collapsible panels, then a
synthesizer lists agreements, disagreements, and unsupported claims and writes one
unified answer that is stored as one node carrying its drafts).

**Tools & media.** Local RAG over PDF/CSV/Markdown/code with citations; vision only to
capable models; web search off by default with a per-chat opt-in and persistent badge;
on-device voice in and out.

## Non-goals for v1

iCloud sync, multi-user, a backend of our own, reselling cloud AI, jailbreak-style
entitlement tricks, and App Store distribution before the on-device milestones are real.

## Privacy invariants, enforced in code

- Keychain for every token; `.afterFirstUnlockThisDeviceOnly`.
- CI fails on `print(` / `NSLog(` / `os_log(`: prompts, responses, attachments, and
  secrets are never logged. Metadata only — ids, enums, counts, byte sizes, durations.
- Every request carries a network class: `.onDevice`, `.privateLan`, `.tailnet`,
  `.publicInternet`. The badge in the header reflects it, and `.publicInternet` requires
  opt-in.
- Release builds contain **zero** ATS exceptions. Plaintext shows a risk badge.
- Temporary chat is backed by a memory-only store; the on-disk store refuses it.

## Success measures for v1

A chat that survives edit/regenerate/branch round trips; a real Ollama server on the LAN
streaming on a physical iPhone; on-device generation that degrades gracefully instead of
terminating; a hybrid turn that visibly shows both drafts and what the synthesis changed;
and a Release build an auditor could confirm has no ATS exception and no payload logging.
