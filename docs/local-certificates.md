# Local certificates for HTTPS, HTTP/3, and WebTransport

Browser HTTP/3 and WebTransport require HTTPS. In development, the cleanest setup is one shared certificate used by both your TCP HTTPS server and Quicsilver's UDP HTTP/3 server.

This doc covers local development. In production, use a publicly trusted certificate and do not use `serverCertificateHashes`.

## The short version

Install and trust a local mkcert root once:

```bash
mkcert -install
```

Generate a short-lived ECDSA certificate before servers start:

```bash
QUICSILVER_DEV_HOSTS=localhost,quicsilver.test,127.0.0.1,::1 \
  bin/rails runner "Quicsilver::Rails::DevWebTransportCertificate.fetch"
```

The helper writes:

```text
tmp/quicsilver/webtransport/localhost.pem
tmp/quicsilver/webtransport/localhost-key.pem
```

Use those same files for:

- Puma/Falcon/reverse-proxy TCP HTTPS
- Quicsilver UDP HTTP/3
- local WebTransport certificate hash metadata

## Why this helper exists

Normal HTTPS page loads and WebTransport both require a secure context, but local WebTransport is pickier than a normal Rails HTTPS page.

`Quicsilver::Rails::DevWebTransportCertificate` generates a local certificate with the shape browsers expect for WebTransport:

- ECDSA P-256 key
- short validity, about 13 days
- SANs for local development hosts
- signed by your local mkcert root when available
- self-signed fallback when mkcert is unavailable

When signed by the mkcert root, the same certificate can be trusted for normal HTTPS and HTTP/3 page/assets, while also qualifying for WebTransport's local certificate hash path.

## Generate before Puma binds

Puma parses its `ssl://...?cert=` bind before Rails finishes booting, so the files must exist before `bin/rails server` starts.

A typical `bin/dev` pre-generates the certificate and then starts Foreman:

```bash
#!/usr/bin/env bash
set -e

export PORT="${PORT:-3443}"
export QUICSILVER_PORT="${QUICSILVER_PORT:-$PORT}"
export QUICSILVER_DEV_HOSTS="${QUICSILVER_DEV_HOSTS:-localhost,quicsilver.test,127.0.0.1,::1}"

bin/rails runner "Quicsilver::Rails::DevWebTransportCertificate.fetch"
exec foreman start -f Procfile.dev "$@"
```

## Use the certificate with Puma

Point Puma's HTTPS bind at the generated files:

```procfile
# Procfile.dev
web: bin/rails server -b 'ssl://127.0.0.1:3443?key=tmp/quicsilver/webtransport/localhost-key.pem&cert=tmp/quicsilver/webtransport/localhost.pem'
```

## Use the same certificate with Quicsilver

Create a small `bin/quicsilver` for the UDP HTTP/3 listener:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "development"

require_relative "../config/environment"
require "quicsilver"
require "quicsilver/rails/dev_web_transport_certificate"

host = ENV.fetch("QUICSILVER_HOST", "0.0.0.0")
port = Integer(ENV.fetch("QUICSILVER_PORT", "3443"))
certificate = Quicsilver::Rails::DevWebTransportCertificate.fetch

configuration = Quicsilver::Transport::Configuration.new(
  certificate.cert_file,
  certificate.key_file,
  idle_timeout_ms: 120_000,
  keep_alive_interval_ms: 20_000,
  max_unidirectional_streams: 100
)

server = Quicsilver::Server.new(
  port,
  address: host,
  app: Rails.application,
  server_configuration: configuration
)

server.start
```

Then run both processes:

```procfile
# Procfile.dev
web: bin/rails server -b 'ssl://127.0.0.1:3443?key=tmp/quicsilver/webtransport/localhost-key.pem&cert=tmp/quicsilver/webtransport/localhost.pem'
h3: bin/quicsilver
```

TCP and UDP can use the same numeric port:

```text
Puma TCP HTTPS:        quicsilver.test:3443
Quicsilver UDP HTTP/3: quicsilver.test:3443
```

## Advertise HTTP/3 with Alt-Svc

The TCP HTTPS response should advertise the UDP HTTP/3 listener:

```ruby
# config/environments/development.rb
config.quicsilver.alt_svc = {
  port: ENV.fetch("QUICSILVER_PORT", 3443).to_i,
  max_age: 3600
}
```

Verify it:

```bash
curl -I https://quicsilver.test:3443/ | grep -i alt-svc
```

Expected:

```text
alt-svc: h3=":3443"; ma=3600
```

Verify direct HTTP/3:

```bash
curl --http3 -I https://quicsilver.test:3443/
```

Expected:

```text
HTTP/3 200
```

## WebTransport certificate hash meta tag

For local WebTransport, render the helper in your layout:

```erb
<%= quicsilver_webtransport_certificate_meta_tag %>
```

The included JavaScript helper reads:

```html
<meta name="quicsilver-webtransport-certificate-sha256" content="...">
```

and passes `serverCertificateHashes` to `new WebTransport(...)` in development.

Production does not render this tag and should use normal public TLS validation.

## Chrome local HTTP/3 behavior

Chrome may not naturally promote local/private-root origins to HTTP/3 through `Alt-Svc`, even when the local root is trusted for TCP HTTPS. This is a browser policy/cache behavior, not a Rails routing issue.

For a repeatable local full-H3 browser test, launch Chrome with a fresh profile and force QUIC for the local origin:

```bash
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --user-data-dir=/tmp/quicsilver-chrome-h3 \
  --origin-to-force-quic-on=quicsilver.test:3443 \
  https://quicsilver.test:3443/
```

With that local override, Chrome DevTools should show `h3` for the document and assets, and WebTransport should connect to the same origin.

Production with a publicly trusted certificate and normal `Alt-Svc` should not need this flag.

## Production notes

Use a publicly trusted certificate, usually on the same host and numeric port for TCP and UDP:

```text
Puma/reverse proxy TCP HTTPS: :443
Quicsilver UDP HTTP/3:        :443
Alt-Svc: h3=":443"; ma=86400
```

Production reminders:

- UDP must be open end-to-end.
- Many L7 load balancers do not pass QUIC/UDP through by default.
- Do not use `serverCertificateHashes` in production.
- Reload Quicsilver when the TLS certificate renews.

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| TCP HTTPS works but `curl --http3` fails | H3 process is not running or UDP is blocked | Start `bin/quicsilver`; check firewall/listener. |
| `Alt-Svc` missing | Middleware not enabled | Set `config.quicsilver.alt_svc`. |
| WebTransport handshake fails locally | Missing hash meta tag, stale generated cert, or unsupported cert shape | Render the meta tag and regenerate with `rm -rf tmp/quicsilver/webtransport`. |
| Chrome DevTools still shows `http/1.1` locally | Chrome did not naturally promote local Alt-Svc | Use the forced local Chrome profile for full-H3 testing. |
| `https://localhost:3443/` refuses connection | You connected by TCP to a UDP-only listener | Navigate to the TCP HTTPS origin; Alt-Svc or forced QUIC handles H3. |

Inspect the generated cert:

```bash
openssl x509 -in tmp/quicsilver/webtransport/localhost.pem -noout -issuer -subject -dates -text | grep -E "Issuer:|Subject:|Not Before|Not After|Public Key Algorithm"
```
