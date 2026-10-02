# frozen_string_literal: true

require "test_helper"

class TransportTest < GigaChatTestCase
  FINGERPRINT = "D2:6D:2D:02:31:B7:C3:9F:92:CC:73:85:12:BA:54:10:35:19:E4:40:5D:68:B5:BD:70:3E:97:88:CA:8E:CF:31"

  def transport(**options) = GigaChat::Internal::Transport.new(GigaChat::Configuration.resolve(options))

  def bundled_root = OpenSSL::X509::Certificate.new(File.read(GigaChat::Internal::Transport::CA_FILE))

  def self_signed_ca
    key = OpenSSL::PKey::EC.generate("prime256v1")
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=Test CA")
    cert.public_key = key
    cert.not_before = Time.now - 60
    cert.not_after = Time.now + 3600
    extensions = OpenSSL::X509::ExtensionFactory.new
    extensions.subject_certificate = extensions.issuer_certificate = cert
    cert.add_extension(extensions.create_extension("basicConstraints", "CA:TRUE", true))
    cert.sign(key, OpenSSL::Digest.new("SHA256"))
  end

  def test_bundled_root_fingerprint_is_pinned
    digest = OpenSSL::Digest::SHA256.hexdigest(bundled_root.to_der).upcase.scan(/../).join(":")

    assert_equal FINGERPRINT, digest, "the bundled PEM must be the genuine Russian Trusted Root CA"
  end

  def test_cert_store_trusts_bundled_root
    assert transport.cert_store.verify(bundled_root), "the client store must trust the bundled root"
  end

  def test_ca_bundle_file_is_appended_not_replacing
    Dir.mktmpdir do |dir|
      extra = self_signed_ca
      path = File.join(dir, "extra.pem")
      File.write(path, extra.to_pem)
      store = transport(ca_bundle_file: path).cert_store

      assert store.verify(extra), "the custom CA must be trusted"
      assert store.verify(bundled_root), "the bundled root must still be trusted"
    end
  end

  def test_missing_ca_bundle_file_raises_configuration_error
    error = assert_raises(GigaChat::ConfigurationError) { transport(ca_bundle_file: "/nonexistent/ca.pem").cert_store }

    assert_match(%r{/nonexistent/ca\.pem}, error.message)
  end

  def test_disabling_verification_warns_and_turns_verify_off
    client_transport = nil

    assert_output(nil, /verification is disabled/) { client_transport = transport(verify_ssl_certs: false) }
    refute_predicate client_transport.api.ssl, :verify?
  end

  def test_chat_v2_url_is_derived_from_base_url
    {
      "https://api.giga.chat/v1" => "https://api.giga.chat/v2/chat/completions",
      "https://api.giga.chat/v1/" => "https://api.giga.chat/v2/chat/completions",
      "https://gigachat.devices.sberbank.ru/api/v1" => "https://gigachat.devices.sberbank.ru/api/v2/chat/completions",
      "https://proxy.local/gigachat" => "https://proxy.local/gigachat/v2/chat/completions"
    }.each do |base_url, expected|
      assert_equal expected, transport(base_url:).chat_v2_url, "for base_url #{base_url}"
    end
  end

  def test_base_url_always_ends_with_slash
    assert_equal "https://gigachat.devices.sberbank.ru/api/v1/",
                 transport(base_url: "https://gigachat.devices.sberbank.ru/api/v1").api.url_prefix.to_s
  end

  def test_default_headers
    headers = transport(client_id: "u1", session_id: "s1").api.headers

    assert_match(%r{\Agigachat-ruby/\d+\.\d+\.\d+ ruby/}, headers["User-Agent"])
    assert_equal "u1", headers["X-Client-ID"]
    assert_equal "s1", headers["X-Session-ID"]
  end

  def test_wrap_errors_maps_faraday_errors
    wrap = ->(error) { GigaChat::Internal::Transport.wrap_errors { raise error, "boom" } }

    assert_raises(GigaChat::APITimeoutError) { wrap.call(Faraday::TimeoutError) }
    error = assert_raises(GigaChat::APIConnectionError) { wrap.call(Faraday::SSLError) }
    assert_match(/Russian Trusted Root CA/, error.message)
    error = assert_raises(GigaChat::APIConnectionError) { wrap.call(Faraday::ConnectionFailed) }
    assert_instance_of Faraday::ConnectionFailed, error.cause
  end

  def test_x_headers_extracts_tracing_headers
    headers = Faraday::Utils::Headers.new.merge("X-Request-ID" => "r", "X-Client-ID" => "c", "Other" => "o")

    assert_equal({ "x-request-id" => "r", "x-client-id" => "c" }, GigaChat::Internal::Transport.x_headers(headers))
  end
end
