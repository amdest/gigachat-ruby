# frozen_string_literal: true

module GigaChat
  module Internal
    # Builds the Faraday connections (API and OAuth) with TLS settings and default headers.
    class Transport
      CA_FILE = File.expand_path("../certs/russian_trusted_root_ca.pem", __dir__)
      USER_AGENT = "gigachat-ruby/#{VERSION} ruby/#{RUBY_VERSION}".freeze
      X_HEADERS = %w[x-request-id x-session-id x-client-id].freeze
      TLS_HINT = "GigaChat certificates chain to the Russian Trusted Root CA; " \
                 "see the TLS section of the gigachat-ruby README"

      def self.wrap_errors
        yield
      rescue Faraday::TimeoutError => e
        raise APITimeoutError, e.message
      rescue Faraday::SSLError => e
        raise APIConnectionError, "#{e.message}. #{TLS_HINT}"
      rescue Faraday::ConnectionFailed => e
        raise APIConnectionError, e.message
      end

      def self.x_headers(headers) = X_HEADERS.to_h { [it, headers[it]] }.compact

      attr_reader :config

      def initialize(config)
        @config = config
        warn_insecure unless config.verify_ssl_certs
      end

      def api = @api ||= connection(base_url, client_cert: true)

      def auth = @auth ||= connection(config.auth_url)

      def base_url = @base_url ||= config.base_url.end_with?("/") ? config.base_url : "#{config.base_url}/"

      # v2 chat lives next to the versioned base path: .../v1/ -> .../v2/chat/completions.
      def chat_v2_url = @chat_v2_url ||= "#{base_url.sub(%r{/v\d+/\z}, "/")}v2/chat/completions"

      # System roots plus the bundled Russian root (and an optional extra bundle); additions never replace.
      def cert_store
        @cert_store ||= OpenSSL::X509::Store.new.tap do |store|
          store.set_default_paths
          store.add_file(CA_FILE) if config.bundled_ca
          add_ca_bundle(store) if config.ca_bundle_file
        end
      end

      private

      def connection(url, client_cert: false)
        request = { timeout: config.timeout, open_timeout: config.open_timeout, write_timeout: config.timeout }
        Faraday.new(url:, headers: default_headers, ssl: ssl_options(client_cert), request:) do |f|
          f.request :multipart
          f.adapter Faraday.default_adapter
        end
      end

      def default_headers
        { "User-Agent" => USER_AGENT, "X-Client-ID" => config.client_id, "X-Session-ID" => config.session_id }.compact
      end

      def ssl_options(client_cert)
        options = { verify: config.verify_ssl_certs, cert_store: }
        return options unless client_cert && config.cert_file

        options[:client_cert] = OpenSSL::X509::Certificate.new(File.read(config.cert_file))
        if config.key_file
          options[:client_key] = OpenSSL::PKey.read(File.read(config.key_file), config.key_file_password)
        end
        options
      end

      def add_ca_bundle(store)
        store.add_file(config.ca_bundle_file)
      rescue OpenSSL::X509::StoreError => e
        raise ConfigurationError, "Cannot load ca_bundle_file #{config.ca_bundle_file}: #{e.message}"
      end

      def warn_insecure
        message = "GigaChat: TLS certificate verification is disabled (verify_ssl_certs: false)"
        config.logger ? config.logger.warn(message) : Kernel.warn(message)
      end
    end
  end
end
