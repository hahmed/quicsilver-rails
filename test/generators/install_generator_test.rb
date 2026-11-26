# frozen_string_literal: true

require "test_helper"
require "rails/generators/test_case"
require "generators/quicsilver/install/install_generator"

class InstallGeneratorTest < Rails::Generators::TestCase
  tests Quicsilver::Generators::InstallGenerator
  destination File.expand_path("../../tmp/install_generator", __dir__)

  setup :prepare_destination

  LAYOUT = <<~ERB
    <!DOCTYPE html>
    <html>
      <head>
        <title>App</title>
        <%= javascript_importmap_tags %>
      </head>
      <body><%= yield %></body>
    </html>
  ERB

  def test_creates_the_scripts_executable
    run_generator

    assert_file "bin/quicsilver", /Quicsilver::Rails::Server\.start/
    assert_file "bin/dev-http3", /bin\/rails quicsilver:certificate/, /foreman start -f Procfile\.http3\.dev/
    assert File.executable?(File.join(destination_root, "bin/quicsilver"))
    assert File.executable?(File.join(destination_root, "bin/dev-http3"))
  end

  # Puma's SSL bind has to read the certificate the gem generates, or the two servers disagree.
  def test_the_procfile_serves_the_certificate_the_gem_generates
    run_generator

    assert_file "Procfile.http3.dev" do |procfile|
      assert_includes procfile, "key=tmp/quicsilver/webtransport/localhost-key.pem&cert=tmp/quicsilver/webtransport/localhost.pem"
      assert_match(/^h3: QUICSILVER_SHUTDOWN_TIMEOUT=3 bin\/quicsilver$/, procfile)
    end
  end

  def test_keeps_the_apps_other_development_processes
    write "Procfile.dev", "web: bin/rails server -p 3000\ncss: bin/rails tailwindcss:watch\n"

    run_generator

    assert_file "Procfile.http3.dev" do |procfile|
      assert_match(/^css: bin\/rails tailwindcss:watch$/, procfile)
      assert_equal 1, procfile.scan(/^web:/).size
    end
  end

  def test_adds_the_meta_tags_to_the_layouts_head
    write "app/views/layouts/application.html.erb", LAYOUT

    run_generator

    assert_file "app/views/layouts/application.html.erb", %r{<%= quicsilver_meta_tags %>\n\s*</head>}
  end

  # Turbo captures the WebSocket class as it loads, so the import has to come first.
  def test_imports_cable_boot_before_everything_else
    write "config/importmap.rb", %(pin "application"\n)
    write "app/javascript/application.js", %(import "@hotwired/turbo-rails"\n)

    run_generator

    assert_file "app/javascript/application.js", /\Aimport "quicsilver\/cable_boot".*\nimport "@hotwired\/turbo-rails"/
  end

  def test_running_again_changes_nothing
    write "app/views/layouts/application.html.erb", LAYOUT
    write "config/importmap.rb", %(pin "application"\n)
    write "app/javascript/application.js", %(import "@hotwired/turbo-rails"\n)
    run_generator

    run_generator

    assert_file "app/views/layouts/application.html.erb" do |layout|
      assert_equal 1, layout.scan("quicsilver_meta_tags").size
    end
    assert_file "app/javascript/application.js" do |javascript|
      assert_equal 1, javascript.scan("quicsilver/cable_boot").size
    end
  end

  # An app without a layout or importmap is told what to add, rather than left to find out.
  def test_says_what_to_add_by_hand_when_it_cannot
    output = run_generator

    assert_match(/add <%= quicsilver_meta_tags %> to your layout/, output)
    assert_match(/import quicsilver\/cable_boot before Turbo/, output)
  end

  private
    def write(path, content)
      full = File.join(destination_root, path)
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, content)
    end
end
