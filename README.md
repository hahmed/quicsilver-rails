# quicsilver-rails

Warning: early experiment.

Rails integration for [Quicsilver](https://github.com/hahmed/quicsilver), a Ruby QUIC and HTTP/3 server.

It serves an existing Rails app over HTTP/3 beside its usual HTTPS server, and can move Action Cable (and so Turbo Streams) onto WebTransport. Controllers, views, assets, cookies and sessions work unchanged.

## What works today

- Advertise HTTP/3 from an existing HTTPS Rails app with `Alt-Svc`.
- Serve the same Rails app over HTTP/3 with Quicsilver, on the same host and port number as TCP HTTPS.
- Normal Rails controllers, middleware, views, assets, cookies and sessions over HTTP/3.
- Action Cable and Turbo Streams over WebTransport, falling back to WebSocket when a client can't use it.
- Experimental WebTransport endpoints for browser realtime streams.

## Requirements

- Ruby 3.4 or newer, the oldest Ruby Quicsilver ships a binary for.
- Rails 8.0 or newer. CI runs Rails 8.0, 8.1 and main.
- Quicsilver 0.6.

## Installation

```ruby
gem "quicsilver-rails"
```

```bash
bundle install
bin/rails generate quicsilver:install
mkcert -install    # once per machine, so browsers trust the development certificate
bin/dev-http3
```

Then open `https://localhost:3443`. The first page arrives over HTTPS, and the next ones over HTTP/3.

The generator writes files you can read and edit, and running it again changes nothing that's already in place:

- **`bin/quicsilver`** starts the HTTP/3 server with `Quicsilver::Rails::Server.start`.
- **`bin/dev-http3`** and **`Procfile.http3.dev`** run Puma on TCP and Quicsilver on UDP, on the same port, the shape production takes. They keep the other processes from your `Procfile.dev`, such as asset watchers.
- **`<%= quicsilver_meta_tags %>`** goes into your layout's `<head>`, and **`import "quicsilver/cable_boot"`** goes at the top of `app/javascript/application.js`, for [Action Cable over WebTransport](#action-cable-and-turbo-streams-over-webtransport).

### The certificate

Browsers check the HTTP/3 server against the certificate they saw over TCP, so Puma and Quicsilver serve the same one. `bin/dev-http3` creates it before either server starts, with `bin/rails quicsilver:certificate`, in `tmp/quicsilver/webtransport/`. It's signed by mkcert's local CA; without mkcert it signs itself, browsers reject it, and the task says so. Set `QUICSILVER_DEV_HOSTS` to add hostnames. See [`docs/local-certificates.md`](docs/local-certificates.md).

### The server

`Server.start` loads the development certificate, tunes the transport for browsers, and writes the transport log through `Rails.logger` (tagged `[quicsilver]`, in `log/<env>.log`), including errors the Rack adapter logs, which would otherwise go to stderr. In development it also logs to the terminal, because this process doesn't go through `rails server`. It takes `port:`, `address:`, `certificate:` and `shutdown_timeout:` keywords, which default to the environment variables below.

### Alt-Svc

Browsers find the HTTP/3 server through an `Alt-Svc` header on the HTTPS responses. It's on whenever `QUICSILVER_PORT` is set, which `bin/dev-http3` does, and advertises that port. A plain `bin/dev` sends none. Turn it off with `config.quicsilver.alt_svc = false`, or pass options, such as a shorter cache time in development:

```ruby
config.quicsilver.alt_svc = { max_age: 60 }   # browsers stop trying a stopped HTTP/3 server sooner
```

In production, use port 443: it's the UDP port networks are most likely to let through.

Check it from the terminal:

```bash
curl -sk -o /dev/null -D - https://localhost:3443/ | grep -i alt-svc   # alt-svc: h3=":3443"; ma=86400
curl -sk --http3-only -o /dev/null -w "%{http_version}\n" https://localhost:3443/   # 3
```

## Environment variables

| Variable | Default | Effect |
|---|---|---|
| `QUICSILVER_PORT` | `3443` | UDP port for HTTP/3, and the port Alt-Svc advertises |
| `QUICSILVER_HOST` | `0.0.0.0` | Address to bind. `0.0.0.0` is IPv4 only; see Quicsilver's notes on IPv6 |
| `QUICSILVER_DEV_HOSTS` | `localhost,127.0.0.1,::1` | Hostnames in the generated development certificate |
| `QUICSILVER_SHUTDOWN_TIMEOUT` | Quicsilver's 30s | Seconds a graceful shutdown on INT or TERM may take. A second signal stops at once |
| `QUICSILVER_DEBUG` | off | Transport detail at DEBUG: a line per request and per response stream. **It includes request headers, cookies among them, so don't share the output** |

## Action Cable and Turbo Streams over WebTransport

Browsers don't expose WebSockets over HTTP/3 to JavaScript, so WebTransport is how a browser gets realtime over QUIC. The adapter carries Action Cable over one WebTransport stream; channels, subscriptions and `turbo_stream_from` are unchanged.

The install generator adds the two pieces it needs. By hand, for an app it couldn't edit: import the boot module **before** Turbo, which captures the WebSocket class as it loads, and render the tags in the layout:

```js
// app/javascript/application.js
import "quicsilver/cable_boot"
import "@hotwired/turbo-rails"
```

```erb
<%# layout <head> %>
<%= quicsilver_meta_tags %>
```

Browsers send no cookies on a WebTransport CONNECT. The page carries them, encrypted, and the cable restores them before `connect` runs, so `ApplicationCable::Connection` needs no change: its usual `cookies` lookup works over both transports. By default that's the Rails session cookie and `session_id`, which is what Devise, `session[:user_id]` and Rails' authentication generator sign in with. If your connection reads another cookie, name it:

```ruby
# config/application.rb
config.quicsilver.cable_cookies = %i[session_token]
```

Only those cookies travel. Logging out revokes the cable if your sessions are database rows; a cookie-store session keeps working until the token expires (a day), as a copied cookie would. See [`docs/action-cable.md`](docs/action-cable.md#authentication).

The importmap pins for `quicsilver/*` are added by the engine.

The cable follows the page:

- A page served over HTTP/3 gets the tags, and the cable uses WebTransport.
- A page served over TCP gets none (`request.http3?` is false), and the cable uses WebSocket.
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
