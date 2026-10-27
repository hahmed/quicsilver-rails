# Action Cable over WebTransport

Experimental. Moves Action Cable's transport from a TCP WebSocket onto an HTTP/3 stream, leaving
channels, subscriptions and the JSON protocol untouched.

## Why WebTransport rather than WebSockets over HTTP/3

RFC 9220 defines WebSockets over HTTP/3, and Quicsilver advertises
`SETTINGS_ENABLE_CONNECT_PROTOCOL`, but **no shipping browser exposes it to JavaScript**. A browser
asked to open a `wss://` URL uses TCP no matter what `Alt-Svc` advertises. For browser realtime over
QUIC, WebTransport is the only path.

Server-to-server clients are a different story, and may prefer Extended CONNECT.

## How it fits together

Action Cable already treats its socket as swappable. `ActionCable::Server::Socket` reads
`@websocket` through a five-method surface — `possible?`, `alive?`, `transmit`, `close`,
`rack_response` — so no Rails change is needed.

| Layer | Piece |
|---|---|
| Rails admission | `Quicsilver::ActionCable::SocketSelection`, prepended by the engine |
| Server transport | `ActionCable::Server::Socket::WebTransport` |
| Wire framing | `Quicsilver::WebTransport::FramedStream` (4-byte big-endian length prefix) |
| Browser transport | `WebTransportSocket` in `quicsilver/action_cable` |

A WebTransport CONNECT to the cable path is dispatched into the Rack app with the session in
`env["quicsilver.webtransport"]`, so Action Cable's mounted server handles it like any other request.
No extra route is needed — do not also mount `webtransport "/cable"`.

WebTransport streams are byte streams, so both sides frame messages identically. A mismatch is
silent corruption rather than an error, which is why the framing has tests on both sides.

## Browser setup

Pin both the adapter and an Action Cable build whose `adapters` object you can reach:

```ruby
# config/importmap.rb
pin "@rails/actioncable", to: "actioncable.esm.js"
pin "quicsilver/action_cable", to: "quicsilver/action_cable.js"
pin "quicsilver/web_transport", to: "quicsilver/web_transport.js"
```

```js
// app/javascript/initializers/quicsilver_cable.js
import * as ActionCable from "@rails/actioncable"
import { cable } from "@hotwired/turbo-rails"
import { installWebTransportCable } from "quicsilver/action_cable"

if (installWebTransportCable({ ActionCable })) {
  cable.setConsumer(ActionCable.createConsumer())
}
```

Each bundled copy of Action Cable has its own `adapters` object — Turbo ships one inlined. Patching
the copy you then build the consumer from, and handing that consumer to Turbo, is what makes
`turbo_stream_from` ride the new transport. `installWebTransportCable` returns `false` where
`WebTransport` is undefined, so the `if` leaves such browsers on WebSockets.

## Development certificates

WebTransport requires HTTPS, and in development the same certificate must serve both listeners. See
[`local-certificates.md`](local-certificates.md), and render the hash meta tag so the browser accepts
a private CA:

```erb
<%= quicsilver_webtransport_certificate_meta_tag %>
```

## Verifying

```bash
rake test_js   # framing and the WebSocket surface, under node
rake test      # the Ruby socket adapter
```

In a browser, a working session shows a `/cable` request with protocol **h3** and no WebSocket entry
in the network panel. `ActionCable.logger.enabled = true` in the console prints the usual
`welcome` / `confirm_subscription` traffic, now arriving over QUIC.

## Known limits

- One reliable bidirectional stream per session, so Action Cable's own multiplexing still applies —
  head-of-line blocking is removed between the cable and other requests, not between channels.
- `Socket#rack_response` accepts the session before the client opens its stream; a client that
  connects and never opens one leaves a session parked until the idle timeout.
- Subscription adapter latency is unchanged. With `solid_cable`, `polling_interval` still bounds how
  fast a broadcast reaches the socket.
