# Installing Cairn on your iPhone from CI (Windows PC, free Apple ID)

How to get a CI-built app onto a physical iPhone **without** the App Store, TestFlight,
or a paid Apple Developer account. Everything personal stays out of the repo: where you
see `your-host.your-tailnet.ts.net`, substitute your real values locally — never commit
them.

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

Remote providers are **HTTPS-only** — the app has no ATS exceptions, so plain
`http://` server URLs are refused. The supported route is Tailscale:

- Install Tailscale on the machine that runs Ollama / LM Studio (the `serve` proxy and
  the inference server must be on the same machine), and on the iPhone (it must stay
  connected for MagicDNS names to resolve).
- One-time on the server (verify flags against `tailscale serve --help` on your build):

  ```bash
  tailscale serve --bg --https=443 11434   # Ollama's default port
  tailscale serve --bg --https=443 1234    # LM Studio's default port
  tailscale serve status
  ```

- Prereqs: MagicDNS on, and HTTPS enabled on the tailnet (Admin console → DNS →
  HTTPS certificates; the interactive `tailscale serve` flow enables it for you).
  `serve` auto-provisions and renews Let's Encrypt certificates for
  `<device>.<tailnet>.ts.net` — iOS trusts them out of the box. No `tailscale cert`
  step, no custom CA, no ATS exceptions.
- In Cairn, the server URL is `https://your-host.your-tailnet.ts.net` (your real
  MagicDNS hostname stays only in the app).

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