# frozen_string_literal: true

module GigaChat
  module Internal
    # Builds the Faraday connections (API and OAuth) with TLS settings and default headers, and runs chat
    # streams over HTTP/2 with httpx: GigaChat's gateway delivers server-sent events incrementally only
    # over HTTP/2 and buffers the whole response over HTTP/1.1, the only version Net::HTTP speaks.
    class Transport
      CA_FILE = File.expand_path("../certs/russian_trusted_root_ca.pem", __dir__)
      USER_AGENT = "gigachat-ruby/#{VERSION} ruby/#{RUBY_VERSION}".freeze
      X_HEADERS = %w[x-request-id x-session-id x-client-id].freeze
      TLS_HINT = "GigaChat certificates chain to the Russian Trusted Root CA; " \
                 "see the TLS section of the gigachat-ruby README"
      # Failures before a connection carries the request; TLS errors are left out on purpose.
      RETRYABLE_CONNECTION_ERRORS = [
        Faraday::ConnectionFailed, HTTPX::ConnectionError, HTTPX::ResolveError, SocketError, SystemCallError, IOError
      ].freeze

      # Raised into the httpx fiber when the caller stops reading early. httpx's error path resets the
      # connection, whereas unwinding past it closes HTTP/2 gracefully and leaves the stream (and GigaChat's
      # generation) running.
      class Aborted < StandardError; end
      private_constant :Aborted

      def self.wrap_errors
        yield
      rescue Faraday::TimeoutError => e
        raise APITimeoutError, e.message
      rescue Faraday::SSLError => e
        raise APIConnectionError, "#{e.message}. #{TLS_HINT}"
      rescue Faraday::ConnectionFailed => e
        raise APIConnectionError, e.message
      end

      def self.retryable_connection_error?(error) = RETRYABLE_CONNECTION_ERRORS.any? { error.is_a?(it) }

      def self.x_headers(headers) = X_HEADERS.to_h { [it, headers[it]] }.compact

      @cert_stores = {}
      @cert_stores_lock = Mutex.new

      # System roots plus the bundled Russian root (and an optional extra bundle); additions never replace.
      # Loading the system roots takes ~3 ms, so clients with the same CA settings share one store. A CA file
      # replaced on disk is picked up after a restart.
      def self.cert_store(bundled_ca:, ca_bundle_file:)
        @cert_stores_lock.synchronize do
          @cert_stores[[bundled_ca, ca_bundle_file]] ||= OpenSSL::X509::Store.new.tap do |store|
            store.set_default_paths
            store.add_file(CA_FILE) if bundled_ca
            add_ca_bundle(store, ca_bundle_file) if ca_bundle_file
          end
        end
      end

      def self.add_ca_bundle(store, path)
        store.add_file(path)
      rescue OpenSSL::X509::StoreError => e
        raise ConfigurationError, "Cannot load ca_bundle_file #{path}: #{e.message}"
      end
      private_class_method :add_ca_bundle

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

      def cert_store
        @cert_store ||= self.class.cert_store(bundled_ca: config.bundled_ca, ca_bundle_file: config.ca_bundle_file)
      end

      # POSTs over HTTP/2 and yields `:head, status, headers`, then `:chunk, bytes` for each body chunk;
      # returns once the body is complete. httpx runs in its own fiber, so the block never runs inside
      # httpx: an exception, break or throw from it aborts the request and resets the connection.
      def stream(path, body:, headers:, timeout: nil)
        fiber = stream_fiber(URI.join(base_url, path).to_s, body, headers, timeout || config.timeout)
        finished = false
        loop do
          event, *args = fiber.resume
          next yield(event, *args) unless event == :done

          finished = true
          response = args.first
          raise_stream_error(response.error) if response.is_a?(HTTPX::ErrorResponse)
          return response
        end
      ensure
        abort_stream(fiber) unless finished
      end

      private

      def stream_session = @stream_session ||= HTTPX.plugin(:callbacks).with(ssl: stream_ssl, headers: default_headers)

      # Callbacks go on a per-request branch: registering them on the shared session would leak them into
      # every later request.
      def stream_fiber(url, body, headers, timeout)
        timeouts = { connect_timeout: config.open_timeout, read_timeout: timeout, write_timeout: timeout }
        session = stream_session
                  .with(timeout: timeouts)
                  .on_response_started { |_request, response| Fiber.yield([:head, response.status, response.headers]) }
                  .on_response_body_chunk { |_request, _response, chunk| Fiber.yield([:chunk, chunk]) }
        Fiber.new { [:done, session.post(url, body:, headers:)] }
      end

      def abort_stream(fiber)
        fiber.raise(Aborted) if fiber&.alive?
      rescue Aborted
        nil
      end

      def raise_stream_error(error)
        case error
        when HTTPX::TimeoutError then raise APITimeoutError, error.message, cause: error
        when OpenSSL::SSL::SSLError then raise APIConnectionError, "#{error.message}. #{TLS_HINT}", cause: error
        else raise APIConnectionError, error.message, cause: error
        end
      end

      def stream_ssl
        options = ssl_options(true)
        { verify_mode: options[:verify] ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE,
          cert_store: options[:cert_store], cert: options[:client_cert], key: options[:client_key] }.compact
      end

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

      def warn_insecure
        message = "GigaChat: TLS certificate verification is disabled (verify_ssl_certs: false)"
        config.logger ? config.logger.warn(message) : Kernel.warn(message)
      end
    end
  end
end
