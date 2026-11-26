// Side-effecting entry point: makes WebTransport the transport Turbo's inlined Action Cable copy
// captures. See captureGlobalWebSocket for why this has to happen before Turbo is evaluated.
//
//   import "quicsilver/cable_boot"        // must come first
//   import "@hotwired/turbo-rails"
//
// The cable follows the page. The tags render only when the page itself arrived over HTTP/3, so a
// page served over TCP keeps Action Cable's own WebSocket. If WebTransport then fails to open,
// the socket falls back to WebSocket for the rest of the page.

import { captureGlobalWebSocket } from "quicsilver/action_cable"

// Rendered by quicsilver_meta_tags, or the cable helpers on their own, only on pages served over
// HTTP/3. The certificate hash alone is not a signal: a page can carry it for WebTransport endpoints
// without asking for its cable to move.
const cableOverWebTransport = document.querySelector(
  'meta[name="quicsilver-cable"], meta[name="quicsilver-cable-cookies"], meta[name="quicsilver-cable-credential"]'
)

if (cableOverWebTransport) {
  const restore = captureGlobalWebSocket()
  if (restore) queueMicrotask(restore)
}
