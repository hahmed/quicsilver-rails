# quicsilver-rails

Warning: early experiment.

Rails integration experiments for [Quicsilver](https://github.com/hahmed/quicsilver), a Ruby HTTP/3/WebTransport server.

This gem is intentionally small right now. The core `quicsilver` gem owns the HTTP/3/WebTransport protocol primitives and exposes a WebTransport session through Rack:

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

The Rails layer should hide raw bytes, stream loops, and protocol framing from app code. The API we want to experiment toward looks more like:

```ruby
class EditorTransport < ApplicationWebTransport::Session
  datagram :cursor, payload: CursorUpdate
  rpc :apply_operation, payload: Operation
  stream :completion, payload: CompletionRequest

  def cursor(update)
    broadcast_cursor update
  end

  def apply_operation(operation)
    document.apply(operation)
  end

  def completion(request)
    Ai.tokens(request.prompt)
  end
end
```

The gem can experiment with that shape before upstreaming missing primitives back into `quicsilver`.

## Action Cable seam

The first compatibility target is Action Cable over one reliable WebTransport bidirectional stream:

```ruby
socket = ActionCable::Server::Socket::WebTransport.new(env, event_target)
```

This adapter shape mirrors Action Cable's internal socket adapter API (`possible?`, `alive?`, `transmit`, `close`, `protocol`, `rack_response`). It is intentionally narrow: Action Cable keeps its own channel multiplexing and message protocol; Quicsilver only supplies the reliable WebTransport pipe.

Because WebTransport streams are byte streams, the adapter uses a small length-prefixed framing layer before handing messages to Action Cable. This replaces WebSocket frame parsing; it does not use Action Cable's Rack-hijack/WebSocket event loop.

## Planned pieces

- Rails route/helper for WebTransport admission
- Rails executor/reloader-safe session runner
- Action Cable transport wiring over one reliable WebTransport bidirectional stream
- JSON/MessagePack codecs and stream framing
- Higher-level datagram/RPC/stream declarations
- Tests around Rails lifecycle, cleanup, and fallback behaviour

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

Experimental. APIs will change.
