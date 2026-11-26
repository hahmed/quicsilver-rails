# Action Cable over WebTransport

Experimental. Moves Action Cable's transport from a TCP WebSocket onto an HTTP/3 stream, leaving
channels, subscriptions and the JSON protocol untouched. Turbo Streams ride along unchanged.

**Requires Rails 8.0 or newer.** CI runs Rails 8.0, 8.1 and main.

## Why WebTransport rather than WebSockets over HTTP/3

RFC 9220 defines WebSockets over HTTP/3, and Quicsilver advertises
`SETTINGS_ENABLE_CONNECT_PROTOCOL`, but **no shipping browser exposes it to JavaScript**. A browser
asked to open a `wss://` URL uses TCP no matter what `Alt-Svc` advertises. For browser realtime over
QUIC, WebTransport is the only path.

Server-to-server clients are a different story, and may prefer Extended CONNECT.

## Setup

Three pieces in the app, none of them in the connection. The importmap pins for `quicsilver/*` come
from the engine.

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

One call in the layout's `<head>`:

```erb
<%# layout <head> %>
<%= quicsilver_meta_tags %>
```

On a page served over HTTP/3 it renders:

- the development certificate hash, so the browser accepts a local CA (development only; see
  [`local-certificates.md`](local-certificates.md));
- the `quicsilver-cable` marker, which tells `cable_boot` to move the cable;
- the cable's cookies, encrypted (see [Authentication](#authentication));
- a separate cable credential, if you pass `cable_credential:`.

On a page served over TCP it renders nothing. The parts are also available on their own as
`quicsilver_webtransport_certificate_meta_tag`, `quicsilver_cable_meta_tag`,
`quicsilver_cable_cookies_meta_tag` and `quicsilver_cable_credential_meta_tag(credential)`.

### 3. Name the cookies the connection reads

```ruby
# config/application.rb
config.quicsilver.cable_cookies = %i[session_token]
```

## Authentication

Browsers send no cookies on a WebTransport CONNECT (the W3C spec fetches it with credentials mode
`omit`), so an unchanged `ApplicationCable::Connection` would find nobody. The page that opens the
cable did arrive with cookies, so the gem gives them back:

1. `quicsilver_meta_tags` encrypts the cookies named in `config.quicsilver.cable_cookies` into a
   token, with a key derived from `secret_key_base`, and renders it.
2. The socket sends the token in its first frame, not the URL, so it stays out of access logs:
   `{"quicsilver_handshake":{"cookies":"…","credential":null}}`.
3. The adapter decrypts it and restores the request's `Cookie` header before `connect` runs. It drops
   any cookie jar memoized earlier (a log tag that reads cookies builds one when the CONNECT is
   logged), and never replaces cookies the request really carried.

Your connection's existing `cookies` lookup then works over both transports.

What to know:

- **Only the listed cookies travel.** With none listed, no token renders and a WebTransport cable is
  anonymous.
- **The token expires after a day.** A reconnect after that waits for the next page load.
- **It is a snapshot.** A cookie rotated after the page rendered arrives stale until the next load.
- **Logout revokes the cable only as well as your lookup does.** A database-backed session stops
  working when its row is deleted. A cookie-store session keeps working until the token expires, as a
  copied cookie would.
- Like any value in the page, a script running in it can read the token. It is only accepted on a
  cable handshake.

### A separate credential

An app that wants the cable to authenticate differently from the page can pass a credential instead.
It travels in the same handshake frame, and the connection reads it through
`quicsilver_cable_credential`, which is `nil` over a WebSocket:

```erb
<%= quicsilver_meta_tags cable_credential: Current.session&.signed_id(purpose: :cable, expires_in: 1.day) %>
```

```ruby
Session.find_signed(quicsilver_cable_credential, purpose: :cable)
```

## Which transport

The cable follows the page, with no configuration:

| Situation | Cable |
|---|---|
| Page arrived over HTTP/3 | WebTransport |
| Page arrived over TCP (first visit, UDP blocked, plain `bin/dev`) | WebSocket. No cable tags render, so `cable_boot` does nothing |
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

Action Cable reads its socket through a six-method surface (`possible?`, `alive?`, `transmit`,
`close`, `protocol`, `rack_response`), so no Rails change is needed. The socket is built in one
constructor, `#initialize(server, env, coder:)`, which Rails 8.0 and 8.1 put in
`ActionCable::Connection::Base` and later Rails moved into `ActionCable::Server::Socket`. The engine
prepends into whichever this Rails has, found by asking for the class rather than by version.

| Layer | Piece |
|---|---|
| Rails admission | `Quicsilver::ActionCable::SocketSelection`, prepended by the engine |
| Server transport | `Quicsilver::ActionCable::Socket` |
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
