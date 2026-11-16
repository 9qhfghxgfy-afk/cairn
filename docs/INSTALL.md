# Installing Cairn on your iPhone from a CI-built IPA — the fallback route

**Prefer [docs/BUILD-MAC.md](BUILD-MAC.md) if you have a Mac.** Building and running from Xcode on
an Apple Silicon Mac is the main loop: it signs with your free Personal Team, it takes seconds rather
than a CI round trip, and it does not need Sideloadly, iTunes, or a Windows machine at all. This file
is the **fallback** for the case where no Mac is available: an unsigned IPA built by CI, signed and
installed from a Windows PC.

How to get a CI-built app onto a physical iPhone **without** the App Store, TestFlight,
or a paid Apple Developer account. Everything personal stays out of the repo: your server's
LAN address, your tunnel address, and your router's dynamic-DNS hostname are typed into the app
only — never committed. These docs use documented placeholder addresses only
(`192.168.1.20`, `192.168.1.0/24`, `10.8.0.2`); the server side of the setup is
[docs/SERVERS.md](SERVERS.md).

## What you need

- Windows PC with **Sideloadly** (v0.71+, sideloadly.io) — plus the **web** versions of
  iTunes and iCloud (uninstall any Microsoft Store versions first; Sideloadly needs the
  web ones).
- iPhone with **Developer Mode** on: Settings → Privacy & Security → Developer Mode →
  enable → restart. (Required on iOS 16+ for any sideloaded app to launch.)
- USB cable (Wi-Fi sideloading works after one USB pairing with "sync over Wi-Fi" on).
- A free Apple ID.

## Free Apple ID limits (Apple's rules, not ours)

- Signatures expire after **7 days**; Sideloadly's automatic app refresh daemon
  re-signs near expiry while the PC can see the phone (USB or Wi-Fi). The clock starts
  at signing time, not at build time.
- At most **3 sideloaded apps** active on a device at once; ~10 App IDs created/year.
- No App Store or TestFlight (that needs the paid Apple Developer Program).
- **No custom entitlements** with a free Apple ID (Sideloadly's entitlements support is
  Apple Developer Program only). Cairn is designed to run without
  `increased-memory-limit`, so this costs you nothing today.

## Build and install

1. GitHub → Actions → **"IPA (unsigned device build)"** → **Run workflow** (main
   branch). Downloads need a signed-in GitHub account even on a public repo.
2. On the finished run, download the **cairn-unsigned-ipa** artifact and unzip it to
   get `Cairn-unsigned.ipa` (the zip-inside-zip is the artifact wrapper).
3. Sideloadly: phone connected and unlocked → drag the IPA in → enter Apple ID
   (keep the default options; enable automatic refresh) → **Start**.
4. Launch Cairn. If it won't open: re-check Developer Mode, device trust, and that the
   PC/phone clocks are correct.

## First-run smoke check (M1 build, mock engine)

- Send a message: user + assistant nodes appear, tokens stream with a tok/s metric.
- Stop mid-stream: partial text stays, node is marked cancelled; relaunch keeps it.
- Regenerate creates a sibling; `< 1 / N >` steps between branches.
- Temporary chat: works, and its content is gone after force-quit (memory-only store).
- Normal chat survives force-quit and reinstall-without-wipe.

## Server access (relevant from Milestone 2 on)

Cairn talks to an inference server you run yourself. Two routes are supported and neither
needs HTTPS, a certificate, or a VPN product beyond your own router:

The server side — binding the port, an optional API key, firewall rules limited to your LAN
subnet, and the WireGuard client config — is in [docs/SERVERS.md](SERVERS.md).

**A. On your own network — the common case.** Add the server's LAN address over `http://`:

```
Name:   Home box
Type:   OpenAI-compatible   (llama.cpp, LM Studio, vLLM, llama-swap, …)
        Ollama              (only for a real Ollama server — see the dialect note)
URL:    http://192.168.1.20:8181     (your own LAN address, typed in the app)
Model:  pick it from the model list, never type it from memory
```

The first time Cairn reaches a LAN address, iOS asks whether Cairn may find and connect to
devices on your local network. **Allow it** — if it is denied, every request to a private
address fails, and Settings → Cairn → Local Network is where it is turned back on.

**B. Away from home — through your router's WireGuard server.** Import the router's WireGuard
client profile into the WireGuard app on iOS, connect, and use **the same private address**,
`http://192.168.1.20:8181`. The tunnel carries the bytes; Cairn never learns the public
endpoint, and the tunnel is the access control.

- `AllowedIPs` in the client config must include your LAN subnet (for example
  `192.168.1.0/24`), or the private address has no route and the request simply fails.
- **Never** point Cairn at your public DDNS hostname with a forwarded inference port. That
  puts an open model endpoint on the internet, and it is not what the tunnel is for.
- At home with the tunnel up and `AllowedIPs 0.0.0.0/0`, the request hairpins out to the
  router's WAN address and back in, which some routers refuse when NAT loopback is off.
  Turn the tunnel off at home, or narrow `AllowedIPs` to the subnets you need.
- Your router's hostname, your tunnel address and its port belong to you: type them into the app,
  never into the repository. `Scripts/check-hostname.sh` fails CI if a real private hostname —
  a VPN DNS name or a dynamic-DNS name — appears in a tracked file, and since 2026-11-15 it also
  fails on any private IP literal that is not one of the documented examples.

**Why plain HTTP is fine on these two routes.** Apple's App Transport Security "applies only to
connections made to public host names" and gives no protection to IP addresses, `.local` hosts,
or unqualified host names, so a private address over `http://` is not blocked and needs no
exception. Inside a WireGuard tunnel the path is already encrypted end to end, so HTTPS there
would encrypt twice and add a certificate to manage for nothing. The app declares exactly one
ATS key, `NSAllowsLocalNetworking`, which covers the remaining case — a `.local` or bare host
*name* — and Apple states that key makes ATS ignore `NSAllowsArbitraryLoads` outright. A
public-internet profile still requires `https://` plus an explicit outbound opt-in, and that rule
is enforced and unit-tested in code, not by an ATS hole. A `Plaintext` badge is shown on any
profile that reaches its server unencrypted, so the trade-off is always visible.

**Dialect note, verified against a real llama.cpp server.** `GET /v1/models` answers with both
an OpenAI-style `data[]` array and an Ollama-style `models` array, while `/api/tags` and
`/api/version` return `404 not_found_error` — the server is **not** Ollama. Choosing **Ollama**
for such a box makes the connection test fail on an endpoint it does not have; choose
**OpenAI-compatible**. A single-model server also ignores the `model` field it is sent, so a
wrong model id produces no error, only a surprise later: always pick the model from the list.

## Troubleshooting

- *"A valid provisioning profile…not found"* / signature errors: fix PC + phone date &
  time, re-sideload.
- Device not detected: install web iTunes (not Store), unlock phone, keep its screen on;
  for Wi-Fi, the phone must be on the same network and previously paired over USB.
- Anisette/login errors (Windows): retry, or use Sideloadly's Advanced → local anisette.
- Installing apps blocked: Settings → Screen Time → Content & Privacy Restrictions →
  iTunes & App Store Purchases → Installing Apps → Allow.

## Refresh cadence

Set Sideloadly's automatic refresh on and leave the PC (or a device-visible network
path) available near day 7 — or just rebuild via **Run workflow** and re-sideload the
new IPA with the same Apple ID before expiry.