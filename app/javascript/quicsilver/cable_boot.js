// Side-effecting entry point: makes WebTransport the transport Turbo's inlined Action Cable copy
// captures. See captureGlobalWebSocket for why this has to happen before Turbo is evaluated.
//
//   import "quicsilver/cable_boot"        // must come first
//   import "@hotwired/turbo-rails"

import { captureGlobalWebSocket } from "quicsilver/action_cable"

// Only where an HTTP/3 listener advertised itself: the meta tag is rendered by
// quicsilver_webtransport_certificate_meta_tag, which is development-only.
if (document.querySelector('meta[name="quicsilver-webtransport-certificate-sha256"]')) {
  const restore = captureGlobalWebSocket()
  if (restore) queueMicrotask(restore)
}
