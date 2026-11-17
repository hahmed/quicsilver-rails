# quicsilver-rails

Warning: early experiment.

Rails integration for [Quicsilver](https://github.com/hahmed/quicsilver), a Ruby QUIC and HTTP/3 server.

It serves an existing Rails app over HTTP/3 beside its usual HTTPS server, and can move Action Cable (and so Turbo Streams) onto WebTransport. Controllers, views, assets, cookies and sessions work unchanged.

## What works today

- Advertise HTTP/3 from an existing HTTPS Rails app with `Alt-Svc`.
- Serve the same Rails app over HTTP/3 with Quicsilver, on the same host and port number as TCP HTTPS.
- Normal Rails controllers, middleware, views, assets, cookies and sessions over HTTP/3.
- Action Cable and Turbo Streams over WebTransport, falling back to WebSocket when a client can't use it. Requires Rails main; see [Requirements](#requirements).
- Experimental WebTransport endpoints for browser realtime streams.

## Requirements

- Ruby 3.4 or newer.
- Quicsilver from `main`.
- **The Action Cable adapter needs Rails main (8.2.0.alpha).** It plugs into `ActionCable::Server::Socket`, which Rails 8.1 and earlier don't have. On those versions the adapter is inert and the cable stays on WebSocket. Serving pages over HTTP/3 doesn't use that seam; the gemspec allows Rails 7.1 and later, but CI only runs against Rails main.

## Installation

```ruby
gem "quicsilver", github: "hahmed/quicsilver"
gem "quicsilver-rails", github: "hahmed/quicsilver-rails"
```

```bash
bundle install
```

A Rails app then needs four small pieces: a certificate shared by both listeners, a `bin/quicsilver` script, a Procfile, and `Alt-Svc`.

### 1. One certificate for both listeners

Browsers validate the HTTP/3 listener against the origin they reached over TCP, so both must serve the same certificate. Trust a local CA once, then generate the certificate:

```bash
mkcert -install
bin/rails runner "Quicsilver::Rails::DevWebTransportCertificate.fetch"
```

It writes `tmp/quicsilver/webtransport/localhost.pem` and `localhost-key.pem`. Without mkcert it falls back to a self-signed certificate that browsers reject. Set `QUICSILVER_DEV_HOSTS` before generating it to add hostnames. See [`docs/local-certificates.md`](docs/local-certificates.md).

### 2. `bin/quicsilver`

```ruby
#!/usr/bin/env ruby
ENV["RAILS_ENV"] ||= "development"

require_relative "../config/environment"

Quicsilver::Rails::Server.start
```

`Server.start` loads the development certificate, tunes the transport for browsers, and writes the transport log through `Rails.logger` (tagged `[quicsilver]`, in `log/<env>.log`). In development it also logs to the terminal, because this process doesn't go through `rails server`. It takes `port:`, `address:`, `certificate:` and `shutdown_timeout:` keywords, which default to the environment variables below.

### 3. Run both listeners

```procfile
# Procfile.dev
web: bin/rails server -b 'ssl://0.0.0.0:3443?key=tmp/quicsilver/webtransport/localhost-key.pem&cert=tmp/quicsilver/webtransport/localhost.pem'
h3: QUICSILVER_SHUTDOWN_TIMEOUT=3 bin/quicsilver
```

Puma serves HTTPS on TCP 3443 and Quicsilver serves HTTP/3 on UDP 3443, which is the shape production takes. foreman kills processes 5s after Ctrl-C, so the shutdown timeout has to fit inside that.

### 4. Advertise HTTP/3

```ruby
# config/environments/development.rb
if ENV["QUICSILVER_PORT"].present?
  config.quicsilver.alt_svc = { port: Integer(ENV["QUICSILVER_PORT"]), max_age: 60 }
end
```

Gating on the port leaves a plain `bin/dev` untouched. `config.quicsilver.alt_svc = true` uses the defaults.

Check it from the terminal:

```bash
curl -sk -o /dev/null -D - https://localhost:3443/ | grep -i alt-svc   # alt-svc: h3=":3443"; ma=60
curl -sk --http3-only -o /dev/null -w "%{http_version}\n" https://localhost:3443/   # 3
```

## Environment variables

| Variable | Default | Effect |
|---|---|---|
| `QUICSILVER_PORT` | `3443` | UDP port for HTTP/3 |
| `QUICSILVER_HOST` | `0.0.0.0` | Address to bind. `0.0.0.0` is IPv4 only; see Quicsilver's notes on IPv6 |
| `QUICSILVER_DEV_HOSTS` | `localhost,127.0.0.1,::1` | Hostnames in the generated development certificate |
| `QUICSILVER_SHUTDOWN_TIMEOUT` | Quicsilver's 30s | Seconds a graceful shutdown on INT or TERM may take. A second signal stops at once |
| `QUICSILVER_DEBUG` | off | Transport detail at DEBUG: a line per request and per response stream. **It includes request headers, cookies among them, so don't share the output** |

## Action Cable and Turbo Streams over WebTransport

Browsers don't expose WebSockets over HTTP/3 to JavaScript, so WebTransport is how a browser gets realtime over QUIC. The adapter carries Action Cable over one WebTransport stream; channels, subscriptions and `turbo_stream_from` are unchanged.

Import the boot module **before** Turbo. Turbo captures the WebSocket class when its module is evaluated, so anything later is too late:

```js
// app/javascript/application.js
import "quicsilver/cable_boot"
import "@hotwired/turbo-rails"
```

Browsers send no cookies on a WebTransport CONNECT, so the page hands the cable a short-lived credential:

```erb
<%# layout <head> %>
<%= quicsilver_webtransport_certificate_meta_tag %>
<%= quicsilver_cable_credential_meta_tag(Current.session&.signed_id(purpose: :cable, expires_in: 1.day)) %>
```

The connection accepts the credential when there's no cookie:

```ruby
# app/channels/application_cable/connection.rb
def find_session
  Session.find_signed(cookies.signed[:session_token]) ||
    Session.find_signed(quicsilver_cable_credential, purpose: :cable)
end
```

The importmap pins for `quicsilver/*` are added by the engine.

The cable follows the page:

- A page served over HTTP/3 renders both tags, and the cable uses WebTransport.
- A page served over TCP renders neither (`request.http3?` is false), and the cable uses WebSocket.
- A WebTransport session that fails to open falls back to WebSocket for the rest of the page, with one console warning.

See [`docs/action-cable.md`](docs/action-cable.md) for how it fits together, verification and limits.

## Running Chrome against it locally

```bash
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --user-data-dir=/tmp/quicsilver-chrome-$(date +%s) \
  --origin-to-force-quic-on=localhost:3443 \
  https://localhost:3443/
```

- Chrome only applies command-line flags to a new browser process. The fresh `--user-data-dir` guarantees one.
- In our testing Chrome didn't switch to HTTP/3 from `Alt-Svc` alone with a locally trusted certificate. `--origin-to-force-quic-on` forces it, but it also skips `Alt-Svc` discovery, so check `Alt-Svc` with `curl`.
- In DevTools, enable the Network panel's Protocol column. Pages and assets should show `h3`.

## Telling which transport you're on

- `request.http3?` is true for requests that arrived over HTTP/3.
- Action Cable labels every cable `[WebSocket]`, whatever the transport, because the adapter presents WebSocket's interface. The request method tells them apart:
  - `Started CONNECT "/cable"` with `REQUEST_METHOD: CONNECT` is WebTransport.
  - `Started GET "/cable"` with `HTTP_UPGRADE: websocket` is a TCP WebSocket.

## Experimental WebTransport endpoints

Apps mount the endpoints they want:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  webtransport "/transports/echo", to: EchoTransport
end
```

See [`docs/webtransport-endpoints.md`](docs/webtransport-endpoints.md) for endpoint classes, browser helpers, and examples for message streams, RPC, server streaming and datagrams.

## Demo app

[`quicsilver-playground`](https://github.com/hahmed/quicsilver-playground) is a full local Rails demo: TCP HTTPS and UDP HTTP/3 on the same port, pages and assets over HTTP/3, `Alt-Svc` verification and a WebTransport echo.

## More documentation

- [`docs/action-cable.md`](docs/action-cable.md): Action Cable over WebTransport, verification and limits.
- [`docs/webtransport-endpoints.md`](docs/webtransport-endpoints.md): routes, endpoint classes, browser helpers and examples.
- [`docs/local-certificates.md`](docs/local-certificates.md): local HTTPS, HTTP/3 and WebTransport certificates, and browser behaviour.

## Development

```bash
bin/setup
bundle exec rake test
```

## Status

Experimental.
