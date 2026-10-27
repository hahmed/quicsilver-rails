// Action Cable over WebTransport.
//
// Action Cable's Connection only touches a handful of WebSocket members, and picks its transport up
// from `adapters.WebSocket`, so a class with that surface is enough to move the cable protocol onto
// an HTTP/3 stream. Channel multiplexing, subscriptions and the JSON protocol are untouched above
// this; only the bytes move differently.
//
// Browsers do not expose WebSocket-over-HTTP/3 to JavaScript, so WebTransport is the only way a
// browser gets realtime over QUIC.

import { connect, readFrames, writeFrame } from "quicsilver/web_transport"

// Connection#getState reads these off the constructor with `for (let state in adapters.WebSocket)`,
// so they must be enumerable own properties, and the names must lowercase to the states it checks
// ("open", "connecting"). Static class fields satisfy both.
export class WebTransportSocket {
  static CONNECTING = 0
  static OPEN = 1
  static CLOSING = 2
  static CLOSED = 3

  constructor(url, protocols = []) {
    this.url = url
    this.readyState = WebTransportSocket.CONNECTING

    // Reported to Connection#isProtocolSupported, which rejects the connection outright when it does
    // not recognise the value. There is no subprotocol negotiation over WebTransport, so both sides
    // assert the same protocol instead: the Ruby adapter's #protocol does the same.
    this.protocol = [].concat(protocols)[0] || "actioncable-v1-json"

    this.onopen = null
    this.onclose = null
    this.onerror = null
    this.onmessage = null

    this.#open()
  }

  send(data) {
    if (this.readyState !== WebTransportSocket.OPEN) return

    // Deliberately not awaited: Connection#send is synchronous and discards the return value. Write
    // failures surface through the transport's closed promise instead.
    writeFrame(this.#writer, data).catch(error => this.#fail(error))
  }

  close() {
    if (this.readyState === WebTransportSocket.CLOSING || this.readyState === WebTransportSocket.CLOSED) return

    this.readyState = WebTransportSocket.CLOSING
    this.#transport?.close()
    this.#closed(1000, "")
  }

  #transport = null
  #writer = null

  async #open() {
    try {
      this.#transport = await connect(httpUrl(this.url))

      const stream = await this.#transport.createBidirectionalStream()
      this.#writer = stream.writable.getWriter()

      this.readyState = WebTransportSocket.OPEN
      this.onopen?.({ target: this })

      this.#transport.closed.then(() => this.#closed(1000, "")).catch(error => this.#fail(error))

      await this.#receive(stream.readable.getReader())
    } catch (error) {
      this.#fail(error)
    }
  }

  async #receive(reader) {
    const decoder = new TextDecoder()

    for await (const frame of readFrames(reader)) {
      // Action Cable expects the WebSocket event shape, and parses event.data itself.
      this.onmessage?.({ data: decoder.decode(frame), target: this })
    }

    this.#closed(1000, "")
  }

  #fail(error) {
    this.onerror?.({ error, target: this })
    this.#closed(1006, String(error?.message || error))
  }

  #closed(code, reason) {
    if (this.readyState === WebTransportSocket.CLOSED) return

    this.readyState = WebTransportSocket.CLOSED
    this.onclose?.({ code, reason, wasClean: code === 1000, target: this })
  }
}

// Action Cable builds ws:// and wss:// URLs; WebTransport takes the https:// origin the HTTP/3
// listener answers on.
export function httpUrl(url) {
  return String(url).replace(/^ws/, "http")
}

// WebTransport needs an HTTP/3 listener, which not every deployment of an app runs. Callers that
// want the cable to fall back to WebSockets rather than fail closed should check this first.
export function supported() {
  return typeof WebTransport !== "undefined"
}

// Point an Action Cable module at WebTransport. Pass the ActionCable module itself — the copy whose
// consumer you are about to create, since each bundled copy has its own adapters object.
//
//   import * as ActionCable from "@rails/actioncable"
//   import { installWebTransportCable } from "quicsilver/action_cable"
//
//   installWebTransportCable({ ActionCable })
export function installWebTransportCable({ ActionCable, force = false } = {}) {
  if (!ActionCable) throw new Error("installWebTransportCable needs the ActionCable module")
  if (!supported() && !force) return false

  ActionCable.adapters.WebSocket = WebTransportSocket
  return true
}
