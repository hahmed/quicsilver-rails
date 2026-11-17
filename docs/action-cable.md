# Action Cable over WebTransport

Experimental. Moves Action Cable's transport from a TCP WebSocket onto an HTTP/3 stream, leaving
channels, subscriptions and the JSON protocol untouched. Turbo Streams ride along unchanged.

**Requires Rails main (8.2.0.alpha).** The adapter plugs into `ActionCable::Server::Socket`, which
Rails 8.1 and earlier don't have. On those versions it is inert and the cable stays on WebSocket.

## Why WebTransport rather than WebSockets over HTTP/3

RFC 9220 defines WebSockets over HTTP/3, and Quicsilver advertises
`SETTINGS_ENABLE_CONNECT_PROTOCOL`, but **no shipping browser exposes it to JavaScript**. A browser
asked to open a `wss://` URL uses TCP no matter what `Alt-Svc` advertises. For browser realtime over
QUIC, WebTransport is the only path.

Server-to-server clients are a different story, and may prefer Extended CONNECT.

## Setup

Three pieces in the app. The importmap pins for `quicsilver/*` come from the engine.

### 1. Boot the transport before Turbo

```js
// app/javascript/application.js
import "quicsilver/cable_boot"   // must come first
import "@hotwired/turbo-rails"
```

Turbo inlines its own copy of Action Cable, and that copy reads the WebSocket class once, when the
module is evaluated. Evaluating Turbo also upgrades the `turbo-cable-stream-source` elements already
in the page, which opens the consumer straight away. By the time a later module could call
`setConsumer`, the cable is already connected over WebSocket.

`cable_boot` swaps `globalThis.WebSocket` for the WebTransport socket, lets Turbo's copy capture it,
and restores the native class immediately so nothing else picks it up by surprise. It only does this
on pages that arrived over HTTP/3; see [Which transport](#which-transport).

### 2. Render the tags

```erb
<%# layout <head> %>
<%= quicsilver_webtransport_certificate_meta_tag %>
<%= quicsilver_cable_credential_meta_tag(Current.session&.signed_id(purpose: :cable, expires_in: 1.day)) %>
```

Both render only when the page arrived over HTTP/3. The certificate tag is development-only: it pins
the local certificate's hash so the browser accepts a private CA. See
[`local-certificates.md`](local-certificates.md).

### 3. Authenticate without cookies

Browsers send no cookies on a WebTransport CONNECT, so the cable can't find the session the usual way.
The page renders a credential instead, and the socket sends it in its first frame:

```json
{"quicsilver_handshake":{"credential":"…"}}
```

The connection reads it through `quicsilver_cable_credential`:

```ruby
# app/channels/application_cable/connection.rb
def find_session
  Session.find_signed(cookies.signed[:session_token]) ||
    Session.find_signed(quicsilver_cable_credential, purpose: :cable)
end
```

Keep the credential short-lived and purpose-scoped, so a leaked one can't stand in for the session
cookie. It travels in a frame, not the URL, so it stays out of access logs. A WebSocket cable sends
cookies as usual, and `quicsilver_cable_credential` is `nil` there.

## Which transport

The cable follows the page, with no configuration:

| Situation | Cable |
|---|---|
| Page arrived over HTTP/3 | WebTransport |
| Page arrived over TCP (first visit, UDP blocked, plain `bin/dev`) | WebSocket. Neither tag renders, so `cable_boot` does nothing |
| WebTransport session fails to open | WebSocket for the rest of the page, with one console warning |
| WebTransport session opened, then dropped | Reconnects over WebTransport |

`request.http3?` exposes the same fact to controllers and views, for features that should degrade
over TCP.

## Without Turbo

An app that builds its own consumer can install the socket on its Action Cable module:

```js
import * as ActionCable from "@rails/actioncable"
import { installWebTransportCable } from "quicsilver/action_cable"

installWebTransportCable({ ActionCable })
const consumer = ActionCable.createConsumer()
```

It returns `false`, and leaves the module alone, where `WebTransport` is undefined.

## How it fits together

`ActionCable::Server::Socket` reads `@websocket` through a five-method surface (`possible?`,
`alive?`, `transmit`, `close`, `rack_response`), so no Rails change is needed.

| Layer | Piece |
|---|---|
| Rails admission | `Quicsilver::ActionCable::SocketSelection`, prepended by the engine |
| Server transport | `ActionCable::Server::Socket::WebTransport` |
| Wire framing | `Quicsilver::WebTransport::FramedStream` (4-byte big-endian length prefix) |
| Browser transport | `WebTransportSocket` in `quicsilver/action_cable` |

A WebTransport CONNECT to the cable path is dispatched into the Rack app with the session in
`env["quicsilver.webtransport"]`, so Action Cable's mounted server handles it like any other request.
No extra route is needed: don't also mount `webtransport "/cable"`.

WebTransport streams are byte streams, so both sides frame messages identically. A mismatch is
silent corruption rather than an error, which is why the framing has tests on both sides.

## Shutdown

On a graceful shutdown Quicsilver sends the session `WT_DRAIN_SESSION`, then closes it with a
`WT_CLOSE_SESSION` capsule. The spec resets a closed session's streams with `WT_SESSION_GONE`; the
socket treats that as the cable closing, not as an error.

## Verifying

```bash
rake test_js   # framing, fallback and the WebSocket surface, under node
rake test      # the Ruby socket adapter
```

In the Rails log, Action Cable labels every cable `[WebSocket]`, because the adapter presents
WebSocket's interface. The request method tells them apart:

```text
Started CONNECT "/cable" [WebSocket] ... (REQUEST_METHOD: CONNECT, ...)       # WebTransport
Started GET "/cable" [WebSocket] ... (... HTTP_UPGRADE: websocket)            # TCP WebSocket
```

In the browser, the network panel shows no WebSocket entry for the cable, and pages show protocol
`h3`. `ActionCable.logger.enabled = true` in the console prints the usual `welcome` /
`confirm_subscription` traffic, now arriving over QUIC.

## Known limits

- One reliable bidirectional stream per session, so Action Cable's own multiplexing still applies.
  Head-of-line blocking is removed between the cable and other requests, not between channels.
- `Socket#rack_response` accepts the session before the client opens its stream. A client that
  connects and never opens one leaves a session parked until the idle timeout.
- Subscription adapter latency is unchanged. With `solid_cable`, `polling_interval` still bounds how
  fast a broadcast reaches the socket.
- Action Cable processes a connection's messages on a thread pool, so a `subscribe` can run before an
  earlier `unsubscribe` of the same stream finishes, raising `AlreadySubscribedError` during Turbo
  navigation. This is Action Cable's behaviour on any transport, but it has shown up more often over
  WebTransport in local testing.
