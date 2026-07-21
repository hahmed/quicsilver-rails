const textEncoder = new TextEncoder()
const textDecoder = new TextDecoder()

export async function connect(url, options = {}) {
  const transport = new WebTransport(url, options)
  await transport.ready
  return transport
}

export async function writeFrame(writer, payload) {
  const bytes = toBytes(payload)
  const frame = new Uint8Array(4 + bytes.length)
  new DataView(frame.buffer).setUint32(0, bytes.length)
  frame.set(bytes, 4)
  await writer.write(frame)
}

export async function* readFrames(reader) {
  let buffer = new Uint8Array(0)

  while (true) {
    const { value, done } = await reader.read()
    if (done) return
    if (!value || value.length === 0) continue

    buffer = concat(buffer, value)

    while (buffer.length >= 4) {
      const length = new DataView(buffer.buffer, buffer.byteOffset, buffer.byteLength).getUint32(0)
      if (buffer.length < 4 + length) break

      yield buffer.slice(4, 4 + length)
      buffer = buffer.slice(4 + length)
    }
  }
}

export async function writeJson(writer, value) {
  await writeFrame(writer, JSON.stringify(value))
}

export async function* readJson(reader) {
  for await (const frame of readFrames(reader)) {
    yield JSON.parse(textDecoder.decode(frame))
  }
}

export async function rpc(transport, request) {
  const stream = await transport.createBidirectionalStream()
  const writer = stream.writable.getWriter()
  const reader = stream.readable.getReader()

  await writeJson(writer, request)
  await writer.close()

  for await (const response of readJson(reader)) {
    return response
  }

  return null
}

export async function* serverStream(transport, request) {
  const stream = await transport.createBidirectionalStream()
  const writer = stream.writable.getWriter()
  const reader = stream.readable.getReader()

  await writeJson(writer, request)
  await writer.close()

  yield* readJson(reader)
}

export async function openMessageStream(transport) {
  const stream = await transport.createBidirectionalStream()
  const writer = stream.writable.getWriter()
  const reader = stream.readable.getReader()

  return {
    send(message) {
      return writeJson(writer, message)
    },

    responses() {
      return readJson(reader)
    },

    close() {
      return writer.close()
    },
  }
}

function toBytes(payload) {
  if (payload instanceof Uint8Array) return payload
  if (payload instanceof ArrayBuffer) return new Uint8Array(payload)
  return textEncoder.encode(String(payload))
}

function concat(left, right) {
  const bytes = new Uint8Array(left.length + right.length)
  bytes.set(left)
  bytes.set(right, left.length)
  return bytes
}
