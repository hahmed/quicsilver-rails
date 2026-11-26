# frozen_string_literal: true

namespace :quicsilver do
  desc "Create the development certificate Puma and Quicsilver serve, unless a valid one exists"
  task certificate: :environment do
    # Run before both servers start, so they don't each generate one and serve different
    # certificates for the same origin.
    certificate = Quicsilver::Rails::DevWebTransportCertificate.fetch
    puts "Development certificate: #{Pathname(certificate.cert_file).relative_path_from(Rails.root)}"

    if certificate.self_signed?
      warn "It is self-signed, so browsers will reject it and stay off HTTP/3. Install mkcert, run " \
        "`mkcert -install`, then delete #{Quicsilver::Rails::DevWebTransportCertificate::DIRECTORY} and run this again."
    end
  end
end
