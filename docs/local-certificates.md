# Local certificates for HTTPS, HTTP/3, and WebTransport

Browser HTTP/3 and WebTransport require HTTPS. In development, the cleanest setup is one shared certificate used by both your TCP HTTPS server and Quicsilver's UDP HTTP/3 server.

This doc covers local development. In production, use a publicly trusted certificate and do not use `serverCertificateHashes`.

## The short version

Trust a local mkcert root once per machine, then let the install generator wire both servers to one
certificate:

```bash
mkcert -install
bin/rails generate quicsilver:install
bin/dev-http3
```

`bin/dev-http3` runs `bin/rails quicsilver:certificate` before either server starts, which writes:

```text
tmp/quicsilver/webtransport/localhost.pem
tmp/quicsilver/webtransport/localhost-key.pem
```

Puma's HTTPS bind in `Procfile.http3.dev` and Quicsilver's `Server.start` both read those files, and
`quicsilver_meta_tags` renders the certificate's hash for WebTransport. To cover more hostnames, set
`QUICSILVER_DEV_HOSTS` and regenerate:

```bash
rm -rf tmp/quicsilver/webtransport
QUICSILVER_DEV_HOSTS=localhost,quicsilver.test,127.0.0.1,::1 bin/rails quicsilver:certificate
```

## Why this helper exists

Normal HTTPS page loads and WebTransport both require a secure context, but local WebTransport is
pickier than a normal Rails HTTPS page.

`Quicsilver::Rails::DevWebTransportCertificate` generates a local certificate with the shape browsers
expect for WebTransport:

- ECDSA P-256 key
- valid for 13 days: WebTransport's `serverCertificateHashes` refuses anything over two weeks
- SANs for local development hosts, with IP addresses (IPv4 and IPv6) as IP entries
- signed by your local mkcert root when available
- self-signed when it isn't, which browsers reject; `quicsilver:certificate` warns when that happens

When signed by the mkcert root, the same certificate is trusted for normal HTTPS and HTTP/3 pages and
assets, while also qualifying for WebTransport's certificate hash path. It's replaced automatically a
day before it expires.

## Why it's generated before the servers start

Puma parses its `ssl://...?cert=` bind before Rails finishes booting, so the files must exist before
`bin/rails server` starts. And two processes generating it at once would each write a different
certificate for the same origin. So `bin/dev-http3` generates it once, then starts foreman.

Without the generator, or with another server such as Falcon, do the same: run
`bin/rails quicsilver:certificate`, then point the server's TLS settings at the two files above.

## Alt-Svc

The HTTPS responses advertise the UDP HTTP/3 server whenever `QUICSILVER_PORT` is set, on that port.
Verify it:

```bash
curl -sI https://localhost:3443/ | grep -i alt-svc   # alt-svc: h3=":3443"; ma=86400
curl --http3-only -sI https://localhost:3443/        # HTTP/3 200
```

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
| TCP HTTPS works but `curl --http3` fails | H3 process is not running or UDP is blocked | Start the app with `bin/dev-http3`; check firewall/listener. |
| `Alt-Svc` missing | `QUICSILVER_PORT` isn't set for the HTTPS server, or `config.quicsilver.alt_svc = false` | Start with `bin/dev-http3`, which sets it. |
| WebTransport handshake fails locally | Missing hash meta tag, stale generated cert, or unsupported cert shape | Render `quicsilver_meta_tags` and regenerate with `rm -rf tmp/quicsilver/webtransport`. |
| Chrome DevTools still shows `http/1.1` locally | Chrome did not naturally promote local Alt-Svc | Use the forced local Chrome profile for full-H3 testing. |
| `https://localhost:3443/` refuses connection | You connected by TCP to a UDP-only listener | Navigate to the TCP HTTPS origin; Alt-Svc or forced QUIC handles H3. |

Inspect the generated cert:

```bash
openssl x509 -in tmp/quicsilver/webtransport/localhost.pem -noout -issuer -subject -dates -text | grep -E "Issuer:|Subject:|Not Before|Not After|Public Key Algorithm"
```
