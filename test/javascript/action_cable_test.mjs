// Transport-level tests for the Action Cable WebTransport socket.
//
// WebTransport itself only exists in a browser, so the global is stubbed here. What these cover is
// the part a browser cannot: that the socket presents the exact surface Action Cable's Connection
// reads, and that framing matches FramedStream byte for byte.
//
//   node --test test/javascript/action_cable_test.mjs

import { test } from "node:test"
import assert from "node:assert/strict"

// Stubs installed before the module under test is imported: it captures nothing at import time, but
// `connect` reads `document` for the development certificate hash.
globalThis.document = { querySelector: () => null }

class FakeWritableStreamDefaultWriter {
  constructor(frames) {
    this.frames = frames
  }

  async write(frame) {
    this.frames.push(frame)
  }

  async close() {}
}

// A real stream stays readable until the peer sends FIN, so an empty queue must park rather than
// report done — otherwise every socket here would close the instant it opened.
class FakeReadableStreamDefaultReader {
  constructor(transport) {
    this.transport = transport
  }

  async read() {
    // Parks for a bounded number of turns rather than forever: a real stream waits on the peer, but
    // a test that never finishes reading would hold the process open after its assertions pass.
    let idle = 0
    while (this.transport.incoming.length === 0 && !this.transport.finished && idle < 50) {
      idle++
      await new Promise(resolve => setImmediate(resolve))
    }

    if (this.transport.incoming.length === 0) return { done: true, value: undefined }
    return { done: false, value: this.transport.incoming.shift() }
  }
}

class FakeWebTransport {
  static lastInstance = null

  constructor(url, options) {
    this.url = url
    this.options = options
    this.written = []
    this.incoming = []
    this.finished = false
    this.ready = Promise.resolve()
    this.closed = new Promise(resolve => { this.resolveClosed = resolve })
    FakeWebTransport.lastInstance = this
  }

  async createBidirectionalStream() {
    return {
      writable: { getWriter: () => new FakeWritableStreamDefaultWriter(this.written) },
      readable: { getReader: () => new FakeReadableStreamDefaultReader(this) },
    }
  }

  close() {
    this.finished = true
    this.resolveClosed()
  }
}

globalThis.WebTransport = FakeWebTransport

const { WebTransportSocket, httpUrl, supported, installWebTransportCable } =
  await import("../../app/javascript/quicsilver/action_cable.js")

function encodeFrame(message) {
  const bytes = new TextEncoder().encode(message)
  const frame = new Uint8Array(4 + bytes.length)
  new DataView(frame.buffer).setUint32(0, bytes.length)
  frame.set(bytes, 4)
  return frame
}

// Opening walks several awaits (transport.ready, createBidirectionalStream, the first read), so one
// turn of the microtask queue is not enough to reach a settled state.
async function settle(turns = 10) {
  for (let turn = 0; turn < turns; turn++) {
    await new Promise(resolve => setImmediate(resolve))
  }
}

test("exposes the ready states Connection#getState enumerates", () => {
  // Connection#getState does `for (let state in adapters.WebSocket)` and lowercases the key, so
  // these must be enumerable own properties of the constructor, not just values on instances.
  assert.deepEqual(Object.keys(WebTransportSocket), ["CONNECTING", "OPEN", "CLOSING", "CLOSED"])
  assert.equal(WebTransportSocket.OPEN, 1)
})

test("converts the cable's ws:// URL to the https:// origin WebTransport needs", () => {
  assert.equal(httpUrl("wss://example.com/cable"), "https://example.com/cable")
  assert.equal(httpUrl("ws://localhost:3443/cable"), "http://localhost:3443/cable")
})

test("reports a protocol Connection#isProtocolSupported accepts", () => {
  const socket = new WebTransportSocket("wss://example.com/cable", ["actioncable-v1-json"])
  assert.equal(socket.protocol, "actioncable-v1-json")

  // Action Cable passes its protocol list, but a caller that passes none must still get a usable
  // value rather than undefined, which Connection would reject as unsupported.
  assert.equal(new WebTransportSocket("wss://example.com/cable").protocol, "actioncable-v1-json")
})

test("opens a bidirectional stream and reports OPEN", async () => {
  const socket = new WebTransportSocket("wss://example.com/cable")
  assert.equal(socket.readyState, WebTransportSocket.CONNECTING)

  let opened = false
  socket.onopen = () => { opened = true }
  await settle()

  assert.equal(FakeWebTransport.lastInstance.url, "https://example.com/cable")
  assert.equal(socket.readyState, WebTransportSocket.OPEN)
  assert.ok(opened)
})

test("frames outbound messages the way FramedStream reads them", async () => {
  const socket = new WebTransportSocket("wss://example.com/cable")
  await settle()

  socket.send(JSON.stringify({ command: "subscribe" }))
  await settle()

  const [frame] = FakeWebTransport.lastInstance.written
  const length = new DataView(frame.buffer, frame.byteOffset, frame.byteLength).getUint32(0)
  assert.equal(length, frame.length - 4)
  assert.equal(new TextDecoder().decode(frame.slice(4)), '{"command":"subscribe"}')
})

test("drops sends made before the stream is open rather than throwing", () => {
  const socket = new WebTransportSocket("wss://example.com/cable")

  // Connection#send guards on isOpen(), but the monitor can race it. Throwing here would escape
  // into Action Cable's reconnect loop.
  assert.doesNotThrow(() => socket.send("{}"))
})

test("delivers each frame as a WebSocket-shaped message event", async () => {
  const socket = new WebTransportSocket("wss://example.com/cable")
  const received = []
  socket.onmessage = event => received.push(event.data)

  const transport = FakeWebTransport.lastInstance
  transport.incoming.push(encodeFrame('{"type":"welcome"}'), encodeFrame('{"type":"ping"}'))
  await settle()
  await settle()

  assert.deepEqual(received, ['{"type":"welcome"}', '{"type":"ping"}'])
})

test("reassembles a message split across chunks", async () => {
  const socket = new WebTransportSocket("wss://example.com/cable")
  const received = []
  socket.onmessage = event => received.push(event.data)

  // QUIC streams are byte streams: a frame can arrive in pieces, and the length prefix itself can
  // straddle a chunk boundary.
  const frame = encodeFrame('{"type":"welcome"}')
  const transport = FakeWebTransport.lastInstance
  transport.incoming.push(frame.slice(0, 2), frame.slice(2, 9), frame.slice(9))
  await settle()
  await settle()

  assert.deepEqual(received, ['{"type":"welcome"}'])
})

test("close() reports a clean WebSocket close once", async () => {
  const socket = new WebTransportSocket("wss://example.com/cable")
  await settle()

  const closes = []
  socket.onclose = event => closes.push(event)
  socket.close()
  socket.close()
  await settle()

  assert.equal(closes.length, 1)
  assert.equal(closes[0].code, 1000)
  assert.ok(closes[0].wasClean)
  assert.equal(socket.readyState, WebTransportSocket.CLOSED)
})

test("a transport that fails reports an unclean close so the monitor reconnects", async () => {
  globalThis.WebTransport = class {
    constructor() {
      this.ready = Promise.reject(new Error("connection refused"))
      this.closed = new Promise(() => {})
    }
  }

  try {
    const socket = new WebTransportSocket("wss://example.com/cable")
    const errors = []
    const closes = []
    socket.onerror = event => errors.push(event.error)
    socket.onclose = event => closes.push(event)
    await settle()
    await settle()

    assert.equal(errors.length, 1)
    assert.equal(closes[0].code, 1006)
    assert.equal(closes[0].wasClean, false)
  } finally {
    globalThis.WebTransport = FakeWebTransport
  }
})

test("installWebTransportCable swaps the adapter and reports support", () => {
  const ActionCable = { adapters: { WebSocket: "original" } }

  assert.ok(supported())
  assert.ok(installWebTransportCable({ ActionCable }))
  assert.equal(ActionCable.adapters.WebSocket, WebTransportSocket)

  assert.throws(() => installWebTransportCable({}), /needs the ActionCable module/)
})

test("installWebTransportCable leaves WebSockets alone where WebTransport is missing", () => {
  const transport = globalThis.WebTransport
  delete globalThis.WebTransport

  try {
    const ActionCable = { adapters: { WebSocket: "original" } }
    assert.equal(supported(), false)
    assert.equal(installWebTransportCable({ ActionCable }), false)
    assert.equal(ActionCable.adapters.WebSocket, "original")
  } finally {
    globalThis.WebTransport = transport
  }
})
