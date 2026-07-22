# HTTP/3 + WebTransport: dev & prod setup

Getting WebTransport to *just work* in a browser is mostly a certificate story, and
Chrome verifies WebTransport certificates under **stricter rules** than a normal
HTTPS page load. The good news: with one correctly-shaped local certificate you can
get **page, assets, and WebTransport all over HTTP/3 locally**, with no Chrome
flags and no manual cert-hash copying.

Target developer experience:

```bash
bin/dev
open https://localhost:3000/
# page + assets load over HTTP/3, "Run echo demo" connects over WebTransport
```

---

## The one thing to understand first

Chrome applies two different certificate checks depending on how a connection is made:

| Path | What Chrome checks |
| --- | --- |
| **Normal HTTPS / HTTP/3 page & asset fetches** | Standard web PKI: the cert must chain to a **trusted root**. For a **locally-installed** root (e.g. mkcert's), Chrome waives the public-cert policies (max validity, Certificate Transparency), which is why a long-lived mkcert cert loads a page fine. |
| **WebTransport** | Same PKI trust **plus** it does *not* get the local-root policy waiver: the leaf must also look like a modern public cert. In practice that means **ECDSA P-256** and **validity ≤ ~14 days**. A `serverCertificateHashes` pin is an *additional* way in, with those same EC/≤14-day constraints. |

This explains everything the playground saw:

- mkcert cert loads the **page** fine (locally-trusted root, policy waived). ✅
- The same mkcert cert fails **WebTransport** with `QUIC_TLS_CERTIFICATE_UNKNOWN`,
  because mkcert issues **RSA + multi-year** leaves and WebTransport rejects that
  shape. ❌ **The blocker was the leaf, not "private roots don't work."**
- A self-signed EC/short-lived cert fixes WebTransport (via pinning) but is **not
  trusted**, so normal page/asset H3 fetches over that endpoint can't verify — which
  is why assets stayed on HTTP/1.1.

### The fix: one leaf that satisfies both

Issue a single **ECDSA P-256, ≤14-day** leaf **signed by the mkcert local root**
(the one already installed via `mkcert -install`). That leaf:

- **chains to a root Chrome trusts** → normal HTTP/3 page & asset fetches verify (CA mode), and
- **is EC P-256 and ≤14 days** → WebTransport accepts it (CA mode, and it also qualifies for pinning as a belt-and-suspenders).

mkcert itself only issues RSA leaves, so don't ask it to make this cert. Instead,
borrow its root key (`$(mkcert -CAROOT)/rootCA-key.pem`) and sign your own EC leaf.
No new trust prompts, because the developer already trusts that root.

> Verified: an EC P-256 / 13-day leaf signed by an RSA mkcert-style root both passes
> `X509::Store` chain verification against that root **and** meets the EC + ≤14-day
> pinning constraints. One cert, both mechanisms.

---

## Development

### 1. Certificate helper (signs with the mkcert root, falls back to self-signed)

`quicsilver-rails` provides `Quicsilver::Rails::DevWebTransportCertificate`.
It generates a 13-day ECDSA P-256 localhost certificate at:

```text
tmp/quicsilver/webtransport/localhost.pem
tmp/quicsilver/webtransport/localhost-key.pem
```

When `mkcert -CAROOT` exposes `rootCA.pem` and `rootCA-key.pem`, the leaf is signed
by that trusted local root. If mkcert is unavailable, the helper falls back to a
self-signed leaf. The fallback still works for WebTransport pinning, but normal
page/asset H3 upgrades will not be trusted.

Use the object API:

```ruby
certificate = Quicsilver::Rails::DevWebTransportCertificate.fetch
certificate.cert_file # tmp/quicsilver/webtransport/localhost.pem
certificate.key_file  # tmp/quicsilver/webtransport/localhost-key.pem
certificate.sha256    # base64 SHA-256 of the DER leaf
```

### 2. Generate the cert before the servers bind, and use it for both

Puma parses its `ssl://...?cert=` bind **before** Rails boots, so the file must
exist first. Generate it at the top of `bin/dev`:

```bash
#!/usr/bin/env bash
set -e
# One shared H3/WebTransport dev cert, signed by the mkcert root.
bin/rails runner "Quicsilver::Rails::DevWebTransportCertificate.fetch"
exec foreman start -f Procfile.dev "$@"
```

`Procfile.dev` — point **both** listeners at the one cert:

```procfile
web: bin/rails server -b 'ssl://127.0.0.1:3000?key=tmp/quicsilver/webtransport/localhost-key.pem&cert=tmp/quicsilver/webtransport/localhost.pem'
h3:  bin/quicsilver
css: bin/rails tailwindcss:watch
```

`bin/quicsilver` uses the same helper (idempotent — reuses the file `bin/dev` wrote):

```ruby
if Rails.env.development?
  certificate = Quicsilver::Rails::DevWebTransportCertificate.fetch
  cert_file = certificate.cert_file
  key_file = certificate.key_file
else
  cert_file = ENV.fetch("TLS_CERT_FILE")
  key_file  = ENV.fetch("TLS_KEY_FILE")
end

Quicsilver::Transport::Configuration.new(cert_file, key_file,
  idle_timeout_ms: 120_000, keep_alive_interval_ms: 20_000, max_unidirectional_streams: 100)
```

### 3. Advertise HTTP/3 so page & assets upgrade

Keep the Alt-Svc header from the TCP origin — now it's honest, because the H3
endpoint presents a trusted cert:

```ruby
# config/environments/development.rb
config.quicsilver.alt_svc = { port: ENV.fetch("QUICSILVER_PORT", 4433).to_i, max_age: 3600 }
# => Alt-Svc: h3=":4433"; ma=3600
```

Chrome loads the page over TCP once, sees Alt-Svc, and moves subsequent same-origin
fetches to HTTP/3 on `:4433`. First paint may show `http/1.1`; reload and the
Network tab shows `h3`.

### 4. One connect helper (keeps pinning as a safety net)

Because the cert is now CA-trusted, WebTransport works in CA mode without hashes.
Keeping the pin costs nothing and makes it bulletproof if Chrome is fussy about the
local root on the QUIC path:

```erb
<%= quicsilver_webtransport_certificate_meta_tag %>
```

```js
export function connectWebTransport(path) {
  const meta = document.querySelector('meta[name="quicsilver-webtransport-certificate-sha256"]')
  const url = new URL(path, location.href)
  url.protocol = "https:"
  url.port = "4433"
  const options = {}
  if (meta) {
    const value = Uint8Array.from(atob(meta.content), c => c.charCodeAt(0))
    options.serverCertificateHashes = [{ algorithm: "sha-256", value }]
  }
  return new WebTransport(url.toString(), options)
}
```

### Optional: same numeric port for TCP and UDP

Running Puma (TCP) and Quicsilver (UDP) both on `:3443` mirrors production and lets
the page and WebTransport share one origin. It is **not required** to get H3 for
assets — a trusted cert on `:4433` + Alt-Svc already does that. (Note: browsing
directly to `https://localhost:4433/` will always show `ERR_CONNECTION_REFUSED`
when only Quicsilver is there, because that's a TCP attempt to a UDP-only port.
That's expected and irrelevant — you navigate to the page origin, not the H3 port.)

---

## Production

Drop pinning entirely and use **CA mode** with a **real, publicly-trusted
certificate** (Let's Encrypt, your org CA). WebTransport verifies exactly like
normal HTTPS. Public CAs already give you everything WebTransport wants: a trusted
chain, Certificate Transparency SCTs, ≤398-day validity, correct SANs,
`serverAuth` EKU.

Recommended topology — TCP and UDP on the **same host:port**, same cert:

```text
Puma  (TCP/TLS, HTTP/1.1+2) :443   ← page + Alt-Svc
Quicsilver (UDP/QUIC, H3)   :443   ← HTTP/3 + WebTransport
Alt-Svc: h3=":443"; ma=86400
```

```ruby
Quicsilver::Transport::Configuration.new(
  ENV.fetch("TLS_CERT_FILE"), # fullchain.pem (leaf + intermediates)
  ENV.fetch("TLS_KEY_FILE")   # privkey.pem
)
```

Production gotchas:

- **UDP must be open and forwarded.** QUIC is UDP; many managed L7 load balancers
  don't do QUIC/UDP passthrough. Terminate QUIC where you can reach UDP directly.
- **No `serverCertificateHashes` in prod** — public certs exceed 14 days and pinning
  would break on every renewal.
- **WebTransport dials the URL authority directly** over QUIC; it does not rely on
  Alt-Svc (that's only for upgrading normal page traffic).
- **Reload the H3 process on cert renewal**, same as any TLS server.

---

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Page loads, but Network tab shows `http/1.1` for document/assets | H3 endpoint cert isn't trusted, so Chrome won't honor Alt-Svc | Serve the mkcert-root-signed EC leaf on the H3 port (above); reload. |
| WebTransport `QUIC_TLS_CERTIFICATE_UNKNOWN` with mkcert | RSA + multi-year leaf; WebTransport rejects that shape | Issue an EC P-256, ≤14-day leaf. |
| WebTransport works but assets still HTTP/1.1 | H3 cert is self-signed (pin-only, untrusted) | Sign the leaf with the mkcert root so it's also CA-trusted. |
| `https://localhost:4433/` → `ERR_CONNECTION_REFUSED` | TCP request to a UDP-only port | Expected. Navigate to the page origin; Alt-Svc handles H3. |
| Pinning still rejected | Leaf is RSA or > 14 days | Regenerate EC `prime256v1`, ≤14 days. |
| Prod H3 dead | UDP blocked/not forwarded | Open UDP end to end. |

Inspect what an H3 endpoint serves (no `openssl s_client` — it can't speak QUIC):

```bash
curl --http3 -v https://localhost:4433/ 2>&1 | grep -iA15 'server certificate'
```

---

## FAQ

**Can one local cert give page/assets + WebTransport over H3, no flags, no manual
hashes?** Yes — an EC P-256, ≤14-day leaf signed by your locally-trusted mkcert
root. That's the whole point of this setup.

**Was mkcert the problem, or private roots in general?** mkcert's **leaf shape**
(RSA + multi-year), not private roots. Chrome trusts the mkcert *root*; it rejected
the *leaf* because WebTransport doesn't get the local-root policy waiver that plain
navigations do. A short-lived EC leaf from the same root satisfies both.

**Does the `:3000` vs `:4433` port difference matter?** No. Alt-Svc advertises H3 on
a different port for the same origin; that's normal. The old errors were cert
errors, not origin errors.

**Do I need `serverCertificateHashes` at all now?** Not strictly — CA mode works
once the leaf is trusted. Keeping it is a harmless safety net for local QUIC
verifier quirks. Never use it in production.

**Should I confirm it's actually on H3?** Yes — reload `https://localhost:3000/` and
check the Network tab's Protocol column shows `h3` for the document and assets.
First hit is TCP; the upgrade lands on reload.
