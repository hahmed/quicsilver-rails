# WebTransport certificates for development and production

Getting WebTransport to work in a browser is mostly a certificate story. Chrome verifies WebTransport certificates under stricter rules than a normal HTTPS page load, so local development and production should use different certificate modes.

## The two browser modes

| Mode | How you opt in | What Chrome checks | Use it for |
| --- | --- | --- | --- |
| CA / PKI mode | Do not pass `serverCertificateHashes` | Normal web PKI: trusted public root, valid SANs, unexpired certificate | Production |
| Pinning mode | Pass `serverCertificateHashes` | Trust store is ignored. Certificate must be ECDSA P-256, valid for 14 days or less, and match the SHA-256 hash | Local development |

Two consequences matter:

- `mkcert` is good for a local HTTPS page, but not for WebTransport pinning. It normally creates long-lived RSA certificates, while Chrome's pinning mode requires ECDSA P-256 and a validity period of 14 days or less.
- `new WebTransport(url)` dials the URL's host and port directly over QUIC. `Alt-Svc` helps normal browser traffic discover HTTP/3, but it is not what makes a WebTransport connection succeed.

## Development

Use two certificates:

- Puma, Falcon, or another TCP HTTPS page server uses `mkcert` for `https://localhost:3000`.
- Quicsilver's HTTP/3/WebTransport listener uses a short-lived ECDSA P-256 self-signed certificate and exposes its SHA-256 hash to the page.

`quicsilver-rails` provides the WebTransport certificate helper:

```ruby
certificate = Quicsilver::Rails::DevWebTransportCertificate.fetch

certificate.cert_file # tmp/quicsilver/webtransport/localhost.pem
certificate.key_file  # tmp/quicsilver/webtransport/localhost-key.pem
certificate.sha256    # base64 SHA-256 of the DER certificate
```

Use that certificate when booting Quicsilver in development:

```ruby
certificate = Quicsilver::Rails::DevWebTransportCertificate.fetch

configuration = Quicsilver::Transport::Configuration.new(
  certificate.cert_file,
  certificate.key_file,
  idle_timeout_ms: 120_000,
  keep_alive_interval_ms: 20_000,
  max_unidirectional_streams: 100
)

Quicsilver::Server.new(
  Integer(ENV.fetch("QUICSILVER_PORT", "4433")),
  address: ENV.fetch("QUICSILVER_HOST", "0.0.0.0"),
  app: Rails.application,
  server_configuration: configuration
).start
```

Add the certificate hash meta tag to your layout in development:

```erb
<%= quicsilver_webtransport_certificate_meta_tag %>
```

It renders:

```html
<meta name="quicsilver-webtransport-certificate-sha256" content="BASE64_SHA256">
```

The JavaScript helper reads that tag automatically. In development it passes `serverCertificateHashes`; in production, where the tag is absent, it uses normal CA / PKI mode.

```js
import { connect } from "quicsilver/web_transport"

const transport = await connect("https://localhost:4433/transports/echo")
```

A typical development process uses mkcert for the page and the Quicsilver dev certificate for WebTransport:

```procfile
web: bin/rails server -b 'ssl://127.0.0.1:3000?key=config/certs/localhost-key.pem&cert=config/certs/localhost.pem'
h3: bin/quicsilver
css: bin/rails tailwindcss:watch
```

## Production

Do not use `serverCertificateHashes` in production. Use CA / PKI mode with a publicly trusted certificate, such as Let's Encrypt.

Recommended topology:

```text
TCP/TLS HTTPS page server :443  -> Rails page + Alt-Svc
UDP/QUIC Quicsilver      :443  -> HTTP/3 + WebTransport
```

TCP and UDP can share the same port number. Use the same public certificate and key for both servers. Serve `Alt-Svc` from the TCP origin so normal page traffic can upgrade to HTTP/3:

```http
Alt-Svc: h3=":443"; ma=86400
```

Point Quicsilver at the full certificate chain and private key:

```ruby
Quicsilver::Transport::Configuration.new(
  ENV.fetch("TLS_CERT_FILE"), # e.g. fullchain.pem
  ENV.fetch("TLS_KEY_FILE")
)
```

Use the full chain, not only the leaf certificate, so clients can build trust correctly.

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `WebTransportError: Opening handshake failed` with `QUIC_TLS_CERTIFICATE_UNKNOWN` | Chrome's WebTransport path does not trust the certificate | In development, use the Quicsilver dev certificate + meta tag. In production, use a publicly trusted certificate. |
| `curl --http3` works but browser WebTransport fails | You are relying on local/private CA trust in Chrome's WebTransport path | Use pinning mode locally. |
| Pinning still fails | Certificate is RSA or valid for more than 14 days | Regenerate as ECDSA P-256 with validity less than or equal to 14 days. |
| Production H3 does not connect | UDP is blocked or not forwarded | Open and forward UDP on the QUIC port. |
| Production breaks after certificate renewal | H3 process still serves the old certificate | Restart or reload Quicsilver when the certificate rotates. |

`openssl s_client` cannot inspect QUIC endpoints. Use curl with HTTP/3 support:

```bash
curl --http3 -v https://localhost:4433/ 2>&1 | grep -iA15 'server certificate'
```

Inspect a local WebTransport development certificate:

```bash
openssl x509 -in tmp/quicsilver/webtransport/localhost.pem -noout -text | grep -iE 'public key algorithm|not after'
openssl x509 -in tmp/quicsilver/webtransport/localhost.pem -outform der | openssl dgst -sha256 -binary | openssl base64
```
