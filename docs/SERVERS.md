# Reaching your own model server from the iPhone

Cairn talks to an inference server you run. Two routes are supported and neither needs a
certificate, a hosted account, or a VPN product beyond your own router:

| Where you are | Route | URL you type in Cairn |
|---|---|---|
| On your own network | The server's LAN address over `http://` | `http://192.168.1.20:8181` |
| Away from home | The **same private address**, carried by your router's WireGuard tunnel | `http://192.168.1.20:8181` |

Every address in this file is a placeholder. Your real LAN address, tunnel address, and your
router's dynamic-DNS hostname are typed into the app and never committed —
`Scripts/check-hostname.sh` fails CI on a real hostname *or* on a private IP literal that is not
one of the documented examples used here.

Plain `http://` to a private address is not an ATS violation and needs no exception: Apple's ATS
"applies only to connections made to public host names", and it gives no protection at all to IP
addresses, unqualified host names, or `.local` hosts. Inside the WireGuard tunnel the path is
already encrypted end to end, so TLS there would encrypt twice and buy a certificate to manage
for nothing. A host on the public internet still has to be `https://`, and that rule lives in
code (`NetworkClass.allowsPlaintext`), not in an ATS hole.

## 1. Bind the server so the LAN can reach it

Most inference servers bind **loopback only** by default, which means the phone cannot connect no
matter what you type in Cairn. Bind the server to all interfaces, or to its LAN address:

```bash
# llama.cpp (llama-server) — OpenAI-compatible API on /v1/...
llama-server -m <model>.gguf --host 0.0.0.0 --port 8181

# LM Studio / vLLM / llama-swap: the same idea, different flag names.
# Check your server's own docs for its host and port options.
```

Why `0.0.0.0` rather than the LAN address itself: `--host 0.0.0.0` listens on every interface, so
the server keeps working if its DHCP address changes. Binding one address (`--host 192.168.1.20`)
is narrower and fine as long as the box has a reserved lease — a server that moves is a server
that stops working.

Give the box a **static address** on the router (a DHCP reservation is enough). A changing LAN
address means editing the profile in the app.

Check it from another device on the same network, not from the server itself:

```bash
curl http://192.168.1.20:8181/v1/models
```

If a model list comes back, Cairn will connect. Connection-refused means the bind address or the
firewall, not Cairn.

## 2. Optional API key

A key on a private server is optional — the firewall and the LAN already decide who arrives. If
you do set one, configure the server to require the standard header:

```bash
llama-server -m <model>.gguf --host 0.0.0.0 --port 8181 --api-key <a-long-random-string>
```

In Cairn the key goes in the profile's **Token** field, which is Keychain-backed
(`.afterFirstUnlockThisDeviceOnly`). Do not put it in a custom header: `Authorization` is refused
by validation on purpose, and other header values land in the settings database, where a secret
does not belong.

Two things worth knowing about a home server:

- **A key sent over `http://` crosses your LAN in the clear.** Cairn warns about exactly that: a
  bearer token on a plaintext profile shows a visible warning on the server row and in the
  editor. On a LAN you control this is usually acceptable; it is not a reason to expose the port
  beyond it.
- **A single-model server ignores the `model` field you send.** A wrong model id produces no
  error, only a surprise later. Always pick the model from the fetched list; typing an id from
  memory is not a supported workflow here.

## 3. Firewall: allow the LAN subnet, forward nothing

Allow the inference port **only from your own subnet**, and create no port forward for it on the
router. That is the entire security model of the LAN route.

```bash
# Linux (ufw): let the LAN subnet in; everything else stays blocked
sudo ufw allow from 192.168.1.0/24 to any port 8181 proto tcp

# Linux (firewalld)
sudo firewall-cmd --permanent --add-rich-rule=\
'rule family="ipv4" source address="192.168.1.0/24" port port="8181" protocol="tcp" accept'
```

On Windows the equivalent is an inbound rule for that port restricted to your subnet, on the
**Private** network profile only.

Two checks prove you built the rule you meant:

- From a phone on your Wi-Fi: `http://192.168.1.20:8181/v1/models` answers.
- From anywhere that is **not** your LAN — a laptop on mobile hotspot, no tunnel — that same
  address must be unreachable. If it answers, something is exposed; fix that before adding a
  profile.

**Never port-forward the inference port to the internet.** An open model endpoint is a free text
generator that anyone on the internet can use, and it is not what the tunnel is for. Away from
home the answer is section 4, not a port forward.

## 4. Away from home: your router's WireGuard server

Use the WireGuard server your router already has (many consumer routers ship one), or run
`wg-quick` on a machine inside the LAN.

1. Generate a client config for the phone and **import it into the WireGuard app on iOS** — scan
   the QR code or open the exported `.conf`.
2. Connect.
3. In Cairn, use **the same private address you use at home**: `http://192.168.1.20:8181`. Cairn
   never learns or needs the router's public endpoint. The tunnel carries the bytes, and the
   tunnel is the access control.

`AllowedIPs` in the **client** config is the setting that decides whether this works. It is a
routing list, not a firewall list: a destination missing from it never enters the tunnel.

```ini
[Interface]
PrivateKey = <phone-private-key>
Address    = 10.8.0.2/24                     # the phone's tunnel address

[Peer]
PublicKey  = <server-public-key>
Endpoint   = <your-router-hostname>:51820    # your own value, typed here, never committed
AllowedIPs = 10.8.0.0/24, 192.168.1.0/24     # the LAN subnet must be in this list
PersistentKeepalive = 25                     # iOS drops idle UDP state
```

- **The LAN subnet must appear in `AllowedIPs`** — here `192.168.1.0/24`. Without it the private
  address has no route and every request fails with a timeout. This is the most common cause of a
  tunnel that "connects but does nothing".
- Prefer listing the subnets you use over `0.0.0.0/0`. With `0.0.0.0/0` while you are *at home*,
  the request hairpins out to the router's WAN address and back in, which some routers refuse when
  NAT loopback is off. Turning the tunnel off at home is the simplest fix.
- If the model box is **not** the router itself, the router must be able to reach the tunnel
  subnet on the LAN and the box must have a return route for it (`10.8.0.0/24 via <router>`). A
  tunnel that reaches the router but not the box is a routing gap on the LAN side, not an app bug.
- `PersistentKeepalive = 25` matters on iOS: without it a quiet tunnel ages out and the first
  request after a break is the one that times out.

## 5. What Cairn shows you

- **Badges on the server row**: `LAN`, `VPN`, or `Internet` for where the address resolves, plus
  `Plaintext` whenever traffic reaches the server unencrypted. The path is never hidden.
- A **warning whenever a token is set on a plaintext profile**, on the row and in the editor.
- The **Local Network prompt** on the first request to a private address. Allow it — denied, every
  request to a private address fails, and Settings → Cairn → Local Network turns it back on.
- A public-internet profile needs `https://` **and** the explicit outbound opt-in, and stays inert
  until you switch that on.

## 6. Setup checklist

1. The server listens on `0.0.0.0` (or a reserved LAN address) on one port.
2. `curl http://<lan-address>:<port>/v1/models` answers from another device on the same network.
3. The firewall allows that port from the LAN subnet only, and no port forward exists.
4. The same address is unreachable from outside the LAN when no tunnel is up.
5. The WireGuard client's `AllowedIPs` includes the LAN subnet.
6. In Cairn: add the profile as **OpenAI-compatible** with `http://<lan-address>:<port>`, **Test**
   reports *Connected*, then pick the model from the fetched list.
7. Away from home: connect the tunnel and use the same address. Nothing else changes.

