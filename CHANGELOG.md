## [Unreleased]

## [0.1.0] - 2026-11-17

### Added

- Action Cable over WebTransport. `quicsilver/action_cable` provides a `WebTransportSocket` with the `WebSocket` surface; `installWebTransportCable({ ActionCable })` swaps it into `@rails/actioncable`, so unchanged channels and `turbo_stream_from` run over one HTTP/3 bidirectional stream. The server adapter plugs into `ActionCable::Server::Socket` (Rails 8.2 / main). Falls back to WebSockets where the browser has no WebTransport.
- A WebTransport cable authenticates with the page's cookies, so `ApplicationCable::Connection` needs no change. Browsers send none on a WebTransport CONNECT; `quicsilver_meta_tags` renders the cookies named in `config.quicsilver.cable_cookies`, encrypted, and the adapter restores them before `connect`. A separate `cable_credential:` remains available.
- `Quicsilver::WebTransport::Channel`: `command`, `stream`, `datagram` and `codec` macros over a WebTransport session, with `connect`/`disconnect` hooks. `StreamHandler` base class for long-lived streams.
- Endpoint classes for RPC, server streaming and message streams, and the `webtransport "/path", to:` route helper.
- `Quicsilver::Rails::DevWebTransportCertificate`: a trusted local certificate shared by the TCP and HTTP/3 listeners, with configurable hosts.
- `Middleware::AltSvc`, inserted by the engine so browsers discover the HTTP/3 listener. It advertises the port the listener binds (`QUICSILVER_PORT`, or 3443).
- Browser helpers (`quicsilver/web_transport`) served as Rails assets.
- A real-peer integration test: Action Cable over an actual Quicsilver server and client.

### Changed

- Depends on quicsilver `~> 0.6.0` from rubygems rather than a git ref. 0.6.0 is the first release with `Server#shutdown_timeout=`, which `QUICSILVER_SHUTDOWN_TIMEOUT` sets.
- `FramedStream` reads the core stream directly; callback-style (`on_data`) streams are no longer adapted.
- A send on a cable socket that is not open reports through `onerror`; `onclose` reports what the transport did rather than what was requested; a second cable stream on a session is closed.

