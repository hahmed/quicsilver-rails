// Side-effecting entry point: makes WebTransport the transport Turbo's inlined Action Cable copy
// captures. See captureGlobalWebSocket for why this has to happen before Turbo is evaluated.
//
//   import "quicsilver/cable_boot"        // must come first
//   import "@hotwired/turbo-rails"
//
// The cable follows the page. Both meta tags render only when the page itself arrived over HTTP/3,
// so a page served over TCP keeps Action Cable's own WebSocket. If WebTransport then fails to open,
// the socket falls back to WebSocket for the rest of the page.

import { captureGlobalWebSocket } from "quicsilver/action_cable"

const servedOverHttp3 = document.querySelector(
  'meta[name="quicsilver-cable-credential"], meta[name="quicsilver-webtransport-certificate-sha256"]'
)

if (servedOverHttp3) {
  const restore = captureGlobalWebSocket()
  if (restore) queueMicrotask(restore)
}
