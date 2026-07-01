# quicsilver-rails

Warning: early experiment.

Rails integration experiments for [Quicsilver](https://github.com/hahmed/quicsilver), a Ruby HTTP/3/WebTransport server.

The core `quicsilver` gem owns the protocol primitives and exposes a WebTransport session through Rack:

```ruby
session = Quicsilver::WebTransport.from_env(request.env)
```

`quicsilver-rails` is where the Rails-shaped API can evolve: routing helpers, Rails executor wrapping, Action Cable over WebTransport, codecs/framing, and higher-level realtime declarations.

## Installation

Add the gems to your Rails application:

```ruby
gem "quicsilver", github: "hahmed/quicsilver"
gem "quicsilver-rails", github: "hahmed/quicsilver-rails"
```

Then run:

```bash
bundle install
```

Mount an endpoint in `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  webtransport "/cursors", to: CursorTransport
end
```

## Current low-level shape

Quicsilver core exposes raw WebTransport primitives. A Rails controller or Rack endpoint can accept a session and hand it to application code:

```ruby
class WebTransportsController < ApplicationController
  def show
    session = Quicsilver::WebTransport.from_env(request.env)
    return head :upgrade_required unless session

    session.accept!

    Thread.new do
      Rails.application.executor.wrap do
        session.each_datagram do |packet|
          session.send_datagram(packet)
        end
      ensure
        session.close
      end
    end

    head :ok
  end
end
```

That is deliberately low-level. It proves the Rack/Rails capability seam, but it is not the final Rails API.

## Direction

Instead of one big WebTransport class, this gem experiments with small endpoint base classes for each transport shape. WebTransport is interesting because it is not just "WebSockets over HTTP/3". It exposes the same transport shapes described by the WebTransport and QUIC specs: unreliable datagrams, reliable unidirectional streams, and reliable bidirectional streams.

### Datagrams: unreliable, unordered messages

WebTransport datagrams are defined as unreliable and unordered. They can be dropped by the network or by congestion control, and the receiver must tolerate loss. That makes them appropriate only for state where a newer update supersedes an older one.

Real-world uses include:

- WebRTC-style media/control data where low latency is more important than retransmitting stale packets
- multiplayer or simulation state snapshots where the next snapshot replaces the previous one
- collaborative cursor or pointer positions where losing an intermediate position is acceptable
- high-frequency sensor or telemetry samples where the application aggregates over time

They are the wrong fit for business events, chat messages, checkout/payment operations, audit trails, or any application write that must be observed exactly once.

```ruby
class CursorTransport < Quicsilver::WebTransport::DatagramEndpoint
  codec :json

  def receive(cursor)
    broadcast_cursor cursor
  end
end
```

### Reliable bidirectional streams: ordered application messages

A WebTransport bidirectional stream is reliable and ordered within that stream. It is the closest fit when replacing a WebSocket-style pipe, because both client and server can send application messages over the same reliable channel.

Real-world uses include:

- Action Cable traffic, where Rails already multiplexes channels and subscriptions at the application layer
- chat, comments, and notifications where messages must not silently disappear
- collaborative editing operations where ordering matters
- session control messages such as subscribe, unsubscribe, acknowledge, or reconnect state

The trade-off is that reliability is not free: delayed data on a stream can delay later data on that same stream. For state that becomes obsolete quickly, prefer datagrams. For state the application must process in order, use a reliable stream.

```ruby
class ChatStream < Quicsilver::WebTransport::MessageStreamEndpoint
  codec :json

  def receive(message)
    Chat.broadcast(message)
  end
end
```

### RPC over a bidirectional stream: one command, one result

A reliable bidirectional stream can also be used as a request/response exchange: the client sends one command and the server sends one result. This is useful for protocol-level operations that are part of a live WebTransport session rather than a separate HTTP request.

Real-world uses include:

- opening or resuming a realtime subscription and returning the accepted server state
- applying a collaborative document operation and returning the committed revision
- acknowledging delivery or synchronization checkpoints
- negotiating capabilities, codecs, or channel membership inside an already-established session

These operations should still be implemented like normal Rails writes: authorize them, validate inputs, use idempotency keys where retries are possible, and persist durable state in the database.

```ruby
class ApplyOperation < Quicsilver::WebTransport::RpcEndpoint
  codec :json

  def perform(operation)
    document.apply(operation)
  end
end
```

### Server streams: reliable progressive output

A WebTransport unidirectional stream is reliable and ordered, but only one side writes to it. That maps naturally to server-produced output where the client starts or joins some work and then receives a sequence of chunks.

Real-world uses include:

- token-by-token AI responses, the same interaction shape used by streaming LLM APIs
- progress output for imports, exports, backups, or deploy/build logs
- tailing logs or other append-only operational output
- streaming query/search results where partial results are useful before the full set is ready

Unlike datagrams, these messages are not disposable. Unlike a general bidirectional message stream, the lifecycle is usually tied to one server-produced result stream.

```ruby
class CompletionStream < Quicsilver::WebTransport::ServerStream
  codec :json

  def perform(request)
    Ai.tokens(request.fetch("prompt"))
  end
end
```

### Picking a transport

| Shape | WebTransport primitive | Delivery | Use it when |
| --- | --- | --- | --- |
| Datagram endpoint | Datagram | unreliable, unordered | newer state replaces older state |
| Message stream endpoint | Bidirectional stream | reliable, ordered | both sides exchange messages that must arrive in order |
| RPC endpoint | Bidirectional stream | reliable request/response | a session command needs a structured result |
| Server stream | Unidirectional stream | reliable, ordered server output | the server emits progressive chunks |


The base classes accept the WebTransport session, run the receive loop, decode messages, encode responses, wrap work in the Rails executor, and close the session. The gem can experiment with this shape before upstreaming missing primitives back into `quicsilver`.

## Action Cable seam

The first compatibility target is Action Cable over one reliable WebTransport bidirectional stream:

```ruby
socket = ActionCable::Server::Socket::WebTransport.new(env, event_target)
```

This adapter shape mirrors Action Cable's internal socket adapter API (`possible?`, `alive?`, `transmit`, `close`, `protocol`, `rack_response`). It is intentionally narrow: Action Cable keeps its own channel multiplexing and message protocol; Quicsilver only supplies the reliable WebTransport pipe.

Because WebTransport streams are byte streams, the adapter uses a small length-prefixed framing layer before handing messages to Action Cable. This replaces WebSocket frame parsing; it does not use Action Cable's Rack-hijack/WebSocket event loop.

## Development

After checking out the repo, run:

```bash
bin/setup
bundle exec rake test
```

You can also run:

```bash
bin/console
```

## Status

Experimental.