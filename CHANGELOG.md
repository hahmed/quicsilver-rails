# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

First release. Requires Ruby 3.4+, Rails 8.0+ and Quicsilver 0.6.

### Added

- Serve a Rails app over HTTP/3, next to its usual HTTPS server, with `Quicsilver::Rails::Server.start`.
- Browsers find the HTTP/3 server on their own: an `Alt-Svc` header advertises it on the port it listens on.
- `request.http3?` tells a controller or view whether the request arrived over HTTP/3.
- A local development certificate that browsers trust, shared by the HTTPS and HTTP/3 servers.
- Action Cable and Turbo Streams over WebTransport, with no changes to your channels. Browsers that can't use WebTransport stay on WebSockets.
- WebTransport cables sign in with the page's cookies, so `ApplicationCable::Connection` doesn't change.
- `quicsilver_meta_tags`, one helper for everything a page's `<head>` needs.
- WebTransport endpoints for realtime features beyond Action Cable: channels, request/response, server streaming, message streams and datagrams, mounted with a `webtransport` route.
- Errors raised in WebTransport handlers go to `Rails.error`; the client gets a generic error.
- Browser JavaScript helpers, pinned in your importmap automatically.
- Quicsilver's logs, and the HTTP/3 server's errors, appear in the Rails log.
- Settings through environment variables: `QUICSILVER_PORT`, `QUICSILVER_HOST`, `QUICSILVER_DEV_HOSTS`, `QUICSILVER_DEBUG` and `QUICSILVER_SHUTDOWN_TIMEOUT`.

[Unreleased]: https://github.com/hahmed/quicsilver-rails/commits/main
