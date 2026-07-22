# WebTransport endpoints

Warning: experimental.

WebTransport is now a [Baseline newly available browser API](https://developer.mozilla.org/en-US/docs/Web/API/WebTransport), but Rails integration and deployment patterns are still early.

WebTransport support in `quicsilver-rails` is an early-adopter API for browser-native realtime streams over HTTP/3. The normal Rails request/response path still runs through your Rack app over HTTP/3; WebTransport is for long-lived sessions that need streams or datagrams.

## Mental model

WebTransport is not a controller action and not an HTTP/1.1 WebSocket upgrade. A browser opens an HTTP/3 Extended CONNECT request with `:protocol = webtransport`. After that request is accepted, the browser and server exchange data inside a WebTransport session.

In Rails, `quicsilver-rails` maps a route to an endpoint class:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  webtransport "/transports/echo", to: EchoTransport
end
```

Endpoint classes usually live in `app/transports`:

```text
app/transports/echo_transport.rb
```

The endpoint owns the WebTransport session lifecycle: accepting streams or datagrams, decoding messages, running application code inside the Rails executor, encoding responses, and closing the session.

## Basic reliable message endpoint

A reliable bidirectional stream is the simplest first endpoint. It is the closest shape to a WebSocket-like application protocol: both sides can send messages, and messages are reliable and ordered within the stream.

```ruby
# app/transports/echo_transport.rb
class EchoTransport < Quicsilver::WebTransport::MessageStreamEndpoint
  codec :json

  def receive(message)
    Rails.logger.info("[echo] #{message.inspect}")
    { echo: message }
  end
end
```

Mount it:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  webtransport "/transports/echo", to: EchoTransport
end
```

Connect from the browser:

```js
import { connect, openMessageStream } from "quicsilver/web_transport"

const transport = await connect("https://quicsilver.test:3443/transports/echo")
const stream = await openMessageStream(transport)

await stream.send({ hello: "world" })

for await (const message of stream.responses()) {
  console.log(message)
  break
}

transport.close()
```

The JavaScript helper handles the 4-byte big-endian length prefix used by `Quicsilver::WebTransport::FramedStream`.

## Development certificate helper

For local WebTransport, render the certificate hash meta tag in your layout:

```erb
<%= quicsilver_webtransport_certificate_meta_tag %>
```

The browser helper reads this tag and passes `serverCertificateHashes` to `new WebTransport(...)` in development. Production does not render this tag and uses normal public TLS validation.

See [`webtransport-certificates.md`](webtransport-certificates.md) for the full local certificate setup.

## Choosing an endpoint shape

| Shape | WebTransport primitive | Delivery | Use it when |
| --- | --- | --- | --- |
| `MessageStreamEndpoint` | Bidirectional stream | reliable, ordered | both sides exchange messages that must arrive in order |
| `RpcEndpoint` | Bidirectional stream | reliable request/response | a session command needs a structured result |
| `ServerStreamingEndpoint` | Unidirectional stream | reliable, ordered server output | the server emits progressive chunks |
| `DatagramEndpoint` | Datagram | unreliable, unordered | newer state replaces older state |

## MessageStreamEndpoint

Use `MessageStreamEndpoint` for reliable, ordered, bidirectional application messages.

Good fits:

- chat-style message exchange
- notification or subscription protocols
- collaborative editing operations where order matters
- WebSocket-like application protocols
- Action Cable-style channel traffic

```ruby
class ChatTransport < Quicsilver::WebTransport::MessageStreamEndpoint
  codec :json

  def receive(message)
    case message.fetch("type")
    when "subscribe"
      subscribe_to_room(message.fetch("room_id"))
      { ok: true, subscribed: message.fetch("room_id") }
    when "message"
      chat_message = ChatMessage.create!(
        room_id: message.fetch("room_id"),
        body: message.fetch("body")
      )

      { ok: true, id: chat_message.id }
    else
      { ok: false, error: "unknown message type" }
    end
  end
end
```

Reliability is not free: delayed data on one stream can delay later data on that same stream. If the state becomes obsolete quickly, use datagrams instead.

## RpcEndpoint

Use `RpcEndpoint` when the client sends one command and expects one structured result inside an existing WebTransport session.

Good fits:

- capability negotiation
- opening or resuming a realtime subscription
- applying a collaborative operation and returning the committed revision
- acknowledging delivery or synchronization checkpoints

```ruby
class ApplyOperationTransport < Quicsilver::WebTransport::RpcEndpoint
  codec :json

  def perform(operation)
    document = Document.find(operation.fetch("document_id"))
    revision = document.apply!(operation.fetch("patch"))

    { ok: true, revision: revision }
  end
end
```

Treat RPC commands like normal Rails writes: authenticate the session, authorize the operation, validate input, and use idempotency keys where retries are possible.

## ServerStreamingEndpoint

Use `ServerStreamingEndpoint` when the client starts or joins work and the server emits a sequence of reliable chunks.

Good fits:

- token-by-token AI responses
- import/export progress
- deploy/build logs
- tailing logs
- streaming search/query results

```ruby
class CompletionTransport < Quicsilver::WebTransport::ServerStreamingEndpoint
  codec :json

  def perform(request)
    AiClient.stream_tokens(request.fetch("prompt")) do |token|
      { token: token }
    end
  end
end
```

Unlike datagrams, server-streamed messages are not disposable. This shape is for output the client should receive in order.

## DatagramEndpoint

Use `DatagramEndpoint` only for unreliable, unordered messages where loss is acceptable.

Good fits:

- collaborative cursor or pointer positions
- game/simulation state snapshots
- high-frequency telemetry samples
- state where the next update replaces the previous one

Bad fits:

- payments or checkout operations
- business events
- chat messages
- audit trails
- any durable write that must be observed exactly once

```ruby
class CursorTransport < Quicsilver::WebTransport::DatagramEndpoint
  codec :json

  def receive(cursor)
    broadcast_cursor(
      user_id: current_user.id,
      x: cursor.fetch("x"),
      y: cursor.fetch("y")
    )
  end
end
```

Datagrams may be dropped by the network or by congestion control. Receivers must tolerate loss, duplication, and reordering.

## Authentication and authorization

A WebTransport session starts as an HTTP/3 request, so cookies and request headers are available at connection time. Do not treat that as enough for the whole session.

Recommended rules:

- authenticate before accepting or processing the session
- authorize every command that mutates or reads protected state
- validate every payload
- apply rate limits for long-lived sessions
- use idempotency keys for retryable writes
- do not use datagrams for durable application operations

## Low-level escape hatch

The endpoint base classes are the recommended Rails-shaped API. If you need lower-level access, Quicsilver core exposes the raw session through the Rack environment:

```ruby
session = Quicsilver::WebTransport.from_env(request.env)
```

Use this only when the endpoint base classes are too restrictive. You are then responsible for accepting the session, stream/datagram loops, Rails executor wrapping, framing, error handling, and closing.

## Testing

See the endpoint tests for executable examples:

- `test/quicsilver/web_transport/message_stream_endpoint_test.rb`
- `test/quicsilver/web_transport/rpc_endpoint_test.rb`
- `test/quicsilver/web_transport/server_streaming_endpoint_test.rb`
- `test/quicsilver/web_transport/datagram_endpoint_test.rb`

## Demo app

See [`quicsilver-playground`](https://github.com/hahmed/quicsilver-playground) for a complete Rails app that serves normal pages/assets over HTTP/3 and includes a browser WebTransport echo demo.
