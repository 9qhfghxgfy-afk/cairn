# Cairn — Clean-Room Functional Specification

This appendix is a **functional** specification. It records what another local-model iOS client
does on screen: which controls exist, what they are labelled, what they do, and what happens when
a control is used. It records **no copied text beyond neutral control labels, no art, no icon
design, no layout measurements, no colour values, and no branding** — those are the parts of
another client that are its expression, and none of them belong here.

Where Cairn makes its own choice instead of matching a recorded behaviour, `docs/PARITY.md` marks
that row `design choice` and says what Cairn does instead. Anything in this document that Cairn
has not built is a gap, not a promise: `docs/PARITY.md` and `ROADMAP.md` are the live record of
what exists.

Privacy invariants this spec must never be read to relax: history, settings and attachments stay
on the device; the network is an opt-in peripheral with a persistent outbound badge; a query
leaves only to the provider the user selected and nothing else; no telemetry, no accounts, no
caps on the user.

---

## 1. Servers

### 1.1 Server list
- One selectable **server type** at a time; the selected server handles all chat requests except
  on-device generation.
- A **built-in on-device engine row** is always present and independent of the server list.
- A **status indicator** per server reflects reachability and selection state.
- A **network-type tag** per server states the environment it belongs to. Cairn's honest classes
  are `Local` (private LAN), `VPN` (mesh-VPN name or `100.64.0.0/10`), and `Public`.
- A **plaintext warning** is shown for a server whose traffic leaves the device unencrypted.
  Plaintext is a warning condition, never a silent one.

### 1.2 On-device engine details
- Expanding the on-device row shows information about the local engine.
- It states that on-device generation runs **regardless of the selected remote server**.
- It offers local-network sharing controls: whether the on-device engine is offered to other
  devices on the local network, and the address and port it is reachable on.

### 1.3 Add / edit server
- Fields: **server name**, **backend type**, **base URL / endpoint**, **API key** or **None**,
  **custom headers**.
- **Backend type** selection lists Ollama, OpenAI-compatible, LM Studio, and other supported
  backend classes; each backend shows its required fields with **example placeholders** and
  reference links for obtaining the needed details.
- **Custom headers**: an arbitrary number of name/value rows, addable and removable. Credential
  values belong in the Keychain, never in these rows — the UI says so.
- **API key / None**: a server may be reached without a credential, or with a bearer token. The
  token is stored in the Keychain only; the row shows whether one is set.

### 1.4 Local-network discovery
- A control **scans the local network** for servers, reports what was found, and **adds a found
  server without requiring a manually typed URL**.
- A **connect action with a live status indicator** reports whether a server is reachable before it
  is saved or used.
- Canceling a scan stops it and clears pending connection attempts.

### 1.5 Setup guidance
- A **setup guide** screen explains how to run a local server and how to connect to a remote one,
  with **step-by-step instructions**, **example addresses**, and **links to provider references**.

---

## 2. Models

### 2.1 Model manager tabs
- **Running** — models currently loaded in memory.
- **Installed** — models available on the selected server.
- **Download** — obtain new models.

### 2.2 Running models
- Empty state: a line stating that no models are loaded plus a hint to load one first.
- Per model: a name plus an action to **unload it** from memory.

### 2.3 Installed models
- Empty state: a line stating that no models are installed plus a hint to download one.
- Per model: name and quantization/version label, expanding into details.
- Details include **size**, **quantization**, and **additional metadata**, with a control to reveal
  the remainder.
- Actions: **load into memory**, **delete model**.

### 2.4 Downloading models
- **Curated entries** with a short description and a size badge.
- **Sort**: by popularity, and by newest.
- **Capability filter**: vision, tools, audio.
- A **search field** doubles as a free-text entry: a full repository identifier can be typed and
  downloaded directly.
- When no curated entry matches the text, the list collapses to a **single install entry** for the
  typed name.
---

## 3. Chat shell

### 3.1 Navigation bar
- Left: opens the **chat-history drawer** containing the chat list plus app navigation.
- Centre: the **current chat title**.
- Right: **new chat** and **settings**.
- A **dashed-outline toggle** in the bar marks a temporary chat.

### 3.2 Empty state
- With no chat to show, the screen offers a route to **configure a server** rather than an inert
  message.

### 3.3 Composer
- A **single-purpose send control** and a **separate add control** that opens a menu of **Photos,
  Camera, Files**.
- A **tools chip** beside the composer opens a menu with **Web Search**, **Web Fetch**,
  **Calculator**.
- A **reasoning-effort control** that changes state when the selected model supports no reasoning.
- A **context-window usage indicator** that expands into **usage detail**, **compact**, and
  **clear**.

### 3.4 Chat drawer
- **New chat**, the searchable **chat list**, **settings**, and **import chat**.

---

## 4. Per-chat configuration sheet

### 4.1 Persona
- **Display name** and **system prompt**.

### 4.2 Model and context size
- **Model selection** for the chat, and **context size** as a **fixed ladder of eight snap
  points**.

### 4.3 Sampling controls
Each control shows its current value, explains itself on request, and offers a way back to the
server's own default.

| Control | Behaviour | Cairn status |
|---|---|---|
| Temperature | slider `0`–`2`, two decimal places, numeric entry, end labels naming the extremes | Cairn: slider + `(i)`, no numeric entry, no end labels |
| Top P | slider `0`–`1` | match |
| Seed | `Random` or `Fixed`; `Fixed` reveals a whole-number entry and a re-roll | Cairn shows the number in both states and re-rolls from the same control |
| Top K | whole-number stepper `1`–`400` | match |
| Min P | slider `0`–`1` | match |
| Max tokens | `Unlimited` or a ladder of power-of-two rungs | Cairn's ladder starts at 256 — `design choice` |
| Repeat penalty | slider `0.50`–`2.00` | Cairn allows `0.0`–`3.0` — `design choice` |
| Repeat last N | ladder `0`–`128` | Cairn allows `0`–`512` — `design choice` |

### 4.4 Overrides and defaults
- A control that is **not set is dimmed**, showing the reference value rather than a value of its
  own, and offers **Use Default** to clear it.
- **Reset To Defaults** clears every knob at once and is destructive: it says so and confirms.
- Cairn today hides a control until it is switched on and offers one "Clear every knob" action —
  `Partial`, see `docs/PARITY.md`.

### 4.5 Save as new model
- Saves the chat's sampling values as a **new named model derived from the current one**, so the
  preset can be reused later.
---

## 5. Settings

### 5.1 Appearance
- A **theme preview card** showing the active theme's **light and dark colour pair** as swatches.
- **Six colour themes.** Each theme supplies both halves; switching theme recolours the whole app
  immediately. Cairn supplies its own palettes and its own names — no palette, iconography or
  colour identity is taken from another client.
- An appearance control that cycles **system**, **light**, **dark**. The cycle action is a button on
  the preview card in the recording; Cairn puts the choice in a picker above the card —
  `design choice`, same three states.

### 5.2 Sections
| Setting | Behaviour |
|---|---|
| Server | a **Manage Servers** row into the server list and its controls |
| Models | a row into the **model manager** for the selected server |
| New Chat | the model and the configuration a new chat starts with |
| Chat Turn | a **send-or-continue** choice: continue the current response, or start a new one |
| System Prompt Context | the context block the model is given, with a summary of what is included |
| Tools | **Web Search**, **Web Fetch**, **Calculator**, plus the search endpoint |
| Web Search | the provider list and the provider in use — see §7 |
| Background Processing | whether a generation may continue while the app is in the background |
| Generation Statistics | token and latency statistics under each generated response |
| Import Chat | import a chat from a file |
| Default Configuration | default persona and sampling values for a new chat, **without** context size |
| About | version, a **privacy statement**, and **licenses** |

Default Configuration carries a note that each server applies only what it supports.

---

## 6. System Prompt Context

### 6.1 Included context toggles
- **Current Date**, **Current Time**, **Platform Info**, **Response Language** — each states what it
  adds.
- **Current Time** warns that precise time is **included in every request and may reduce caching on
  some server types**; enabling it requires confirming that warning.

### 6.2 Behaviour
- Toggled items are **appended to the system message** the model receives.
- A **live preview** shows the exact block that goes on the wire. Cairn's preview is byte-identical
  to the request's system message, so the preview cannot drift from what is sent.
- Cairn states the values as prose ("Today is Friday, November 12, 2025.") rather than a bracketed
  tag list — `design choice`; the content is the same and the preview shows it exactly.

### 6.3 Tool-activated context
- Selecting a web tool adds a block explaining **when to call which tool**.
- Selecting a file tool adds **file-handling instructions**.
- Selecting an image-capable model with an image present adds **image-handling instructions**.

---

## 7. Web Search

### 7.1 Providers
- **DuckDuckGo** is the built-in default: no key, no account, nothing to configure, and the row
  cannot be deleted.
- A **custom SearXNG instance** is the self-hosted choice. Each instance is its own provider row with
  a name, an address, optional query parameters and an optional credential; several can exist and one
  is selected.
- An **Ollama Cloud search tool** is offered while the matching cloud server profile and its key
  exist. It appears automatically and disappears automatically; it is not hand-added.

### 7.2 Selection and failure
- The **selected provider is the only provider a search uses**. There is **no silent fallback**: if
  the selected provider fails, the tool returns a typed error naming the provider and the reason.
- A provider that fails is **not** switched automatically. The user chooses, or chooses nothing.
- If the selected provider **disappears** — its row deleted, or the cloud profile or its key removed —
  selection reverts to the built-in DuckDuckGo row, and Settings says plainly that it did and why. A
  public-internet provider still needs the outbound acknowledgement before any query leaves.

### 7.3 Consent, disclosure, attribution
- The **first use** of a web tool states which provider is active and what leaves the device, and
  asks. Declining is remembered: the tool returns a typed refusal and **no request is made**.
- An **outbound badge** is shown for as long as the app's web tools are enabled and the active
  provider is on the public internet — before the first query, not only after one.
- With DuckDuckGo active, the UI states that results come from DuckDuckGo and that Cairn is not
  affiliated with it.
- **Only the query text** is sent, plus the provider's own request parameters. No conversation text,
  no system prompt, no persona and no attachment travels in a search request.
- Nothing is cached to disk and nothing is logged but typed metadata: provider, network class, result
  count, duration, failure kind.
- DuckDuckGo is used as a **regular HTTPS client, one request per search**, with no rotation, no
  cookie and no fingerprint evasion. Results are shown to the user and are not resold.

### 7.4 Custom provider controls
- A row shows: name, endpoint, the parameters it adds, whether a credential is stored, and its network
  class.
- Editing a row covers: display name, base URL including a reverse-proxy subpath, categories,
  language, safe-search level, time range, result count, timeout, and a credential.
- The credential is either a bearer token or a named secret header, held in the Keychain service used
  for search credentials. Ordinary header rows must not carry credentials; credential-looking header
  names are refused with an explanation.
- Public endpoints require `https`. A private LAN or tunnel address may use `http`, carries the
  `Plaintext` badge, and follows the existing transport rules.
- **Test Connection** runs one fixed harmless query and reports one of: success with a count and a
  latency; host unreachable; a Local Network permission refusal; `403`, which usually means the
  instance does not allow `format=json`; rate limited; or an unreadable response.
- A **setup guide** explains how to enable JSON output on a SearXNG instance, how to reach it over a
  LAN or tunnel address, and that a publicly reachable instance should be served over `https`.

---

## 8. Invariants this specification must not relax

1. Chat history, settings and attachments stay on the device unless the user opts out of that.
2. No subscription, no paywall, no message cap, no telemetry, no ads, no account.
3. Anything that leaves the device needs an explicit opt-in first and a persistent badge after.
4. A search query goes to the selected provider and nowhere else.
5. Secrets live in the Keychain: not in UserDefaults, not in a plist, not in a log, not in a
   repository.
6. No code, string, asset, layout or colour identity from another client.

---

## 9. Glossary

| Term | Meaning here |
|---|---|
| Provider | One configured search backend: built-in DuckDuckGo, a SearXNG instance, or Ollama Cloud search. |
| Active provider | The single provider a search may use. |
| Keyless | Needs no credential. DuckDuckGo is keyless because it needs no key, not because a key is unavailable. |
| Endpoint | The base address of a provider, including any reverse-proxy subpath. |
| Network class | Cairn's honest label for where a request goes: local network, private tunnel, public internet. |
| Outbound badge | The persistent mark that this app, or this conversation, has let data leave the device. |
| Typed failure | A named failure the model can see and act on, never an empty result standing in for one. |



