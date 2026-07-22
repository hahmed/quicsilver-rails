# quicsilver-rails

Warning: early experiment.

Rails integration for [Quicsilver](https://github.com/hahmed/quicsilver), a Ruby QUIC and HTTP/3 server.

`quicsilver-rails` adds Rails-shaped integration points to make it easier to get started: Alt-Svc middleware, Rails executor wrapping, local development certificate helpers, WebTransport routing helpers, endpoint base classes, browser JavaScript helpers, and an experimental Action Cable socket adapter.

## What works today

- Advertise HTTP/3 from an existing HTTPS Rails app with `Alt-Svc`.
- Serve the same Rails Rack app over HTTP/3 with Quicsilver.
- Use normal Rails controllers, middleware, views, and assets over H3.
- Run local TCP HTTPS and UDP HTTP/3 on the same host and port.
- Add experimental WebTransport endpoints for browser realtime streams.

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

## HTTP/3 discovery with Alt-Svc

HTTP/3 is discovered through `Alt-Svc`:

```http
Alt-Svc: h3=":443"; ma=86400
```

A typical setup has two listeners for the same Rails app:

- HTTPS over TCP for normal browser discovery, usually Puma/Falcon/reverse proxy.
- HTTP/3 over UDP served by Quicsilver.

Enable the provided middleware:

```ruby
# config/environments/development.rb
config.quicsilver.alt_svc = {
  port: ENV.fetch("QUICSILVER_PORT", 3000).to_i,
  max_age: 86_400
}
```

Or use default options:

```ruby
config.quicsilver.alt_svc = true
```

Verify the TCP response advertises HTTP/3:

```bash
curl -I https://quicsilver.test:3000/ | grep -i alt-svc
```

Expected:

```text
alt-svc: h3=":3000"; ma=86400
```

Then verify direct HTTP/3:

```bash
curl --http3 -I https://quicsilver.test:3000/
```

Expected:

```text
HTTP/3 200
```

## Local development certificates

Browser HTTP/3 and WebTransport require HTTPS. In development, generate one shared certificate and use it for both your TCP HTTPS server and Quicsilver's UDP HTTP/3 server.

Install and trust a local development CA once:

```bash
mkcert -install
```

Generate/cache the certificate before starting your servers:

```bash
bin/rails runner "Quicsilver::Rails::DevWebTransportCertificate.fetch"
```

The helper writes:

```text
tmp/quicsilver/webtransport/localhost.pem
tmp/quicsilver/webtransport/localhost-key.pem
```

Use those files for Puma's HTTPS bind:

```procfile
# Procfile.dev
web: bin/rails server -b 'ssl://127.0.0.1:3443?key=tmp/quicsilver/webtransport/localhost-key.pem&cert=tmp/quicsilver/webtransport/localhost.pem'
```

Use the same files when starting Quicsilver:

```ruby
# bin/quicsilver
#!/usr/bin/env ruby
# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "development"

require_relative "../config/environment"
require "quicsilver"
require "quicsilver/rails/dev_web_transport_certificate"

host = ENV.fetch("QUICSILVER_HOST", "0.0.0.0")
port = Integer(ENV.fetch("QUICSILVER_PORT", "3443"))
certificate = Quicsilver::Rails::DevWebTransportCertificate.fetch

configuration = Quicsilver::Transport::Configuration.new(
  certificate.cert_file,
  certificate.key_file,
  idle_timeout_ms: 120_000,
  keep_alive_interval_ms: 20_000,
  max_unidirectional_streams: 100
)

server = Quicsilver::Server.new(
  port,
  address: host,
  app: Rails.application,
  server_configuration: configuration
)

server.start
```

Then run both processes:

```procfile
# Procfile.dev
web: bin/rails server -b 'ssl://127.0.0.1:3443?key=tmp/quicsilver/webtransport/localhost-key.pem&cert=tmp/quicsilver/webtransport/localhost.pem'
h3: bin/quicsilver
```

TCP and UDP can use the same numeric port, which mirrors production:

```text
Puma TCP HTTPS:        127.0.0.1:3443
Quicsilver UDP HTTP/3: 127.0.0.1:3443
```

The helper signs with the local `mkcert` root when available, and falls back to self-signed certificates. To include custom local hostnames in the generated certificate, set `QUICSILVER_DEV_HOSTS` before generating it:

```bash
QUICSILVER_DEV_HOSTS=localhost,quicsilver.test,127.0.0.1,::1 \
  bin/rails runner "Quicsilver::Rails::DevWebTransportCertificate.fetch"
```

If you use WebTransport in development, add the helper meta tag to your layout:

```erb
<%= quicsilver_webtransport_certificate_meta_tag %>
```

The included JavaScript helper reads this tag and passes `serverCertificateHashes` to `new WebTransport(...)` in development. Production does not render this tag and uses normal public TLS validation.

See [`docs/webtransport-certificates.md`](docs/webtransport-certificates.md) for details.

## Running HTTP/3 locally in Chrome

For local Chrome testing with a private development CA, you may need to force QUIC for the origin:

```bash
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --user-data-dir=/tmp/quicsilver-chrome-h3 \
  --origin-to-force-quic-on=quicsilver.test:3000 \
  https://quicsilver.test:3000/
```

This is a local development workaround. Production deployments with a publicly trusted certificate and normal `Alt-Svc` should not need this flag.

## Experimental WebTransport endpoint

WebTransport support is early, but useful for trying browser-native bidirectional streams over HTTP/3.

Mount an endpoint in `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  webtransport "/echo", to: EchoTransport
end
```

Define a transport:

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

Use the browser helper:

```js
import { connect, openMessageStream } from "quicsilver/web_transport"

const transport = await connect("https://quicsilver.test:3000/echo")
const stream = await openMessageStream(transport)

await stream.send({ hello: "world" })

for await (const message of stream.responses()) {
  console.log(message)
  break
}

transport.close()
```

The helper handles the 4-byte length-prefixed JSON framing used by `Quicsilver::WebTransport::FramedStream`.

## Experimental Action Cable adapter

`quicsilver-rails` includes an experimental Action Cable socket adapter over one reliable WebTransport bidirectional stream:

```ruby
socket = ActionCable::Server::Socket::WebTransport.new(env, event_target)
```

This targets Rails' internal socket seam and is not yet the recommended production path.

## Demo app

See [`quicsilver-playground`](https://github.com/hahmed/quicsilver-playground) for a full local Rails demo with:

- TCP HTTPS and UDP HTTP/3 on the same host and port.
- ordinary Rails page/assets over HTTP/3.
- `Alt-Svc` verification.
- browser WebTransport echo.

## Development

After checking out the repo, run:

```bash
bin/setup
bundle exec rake test
```

## Status

Experimental.
