# frozen_string_literal: true

module GigaChat
  # Entry point to the GigaChat REST API. Thread-safe: share one instance across threads.
  class Client
    AUTH_OPTIONS = %i[credentials scope access_token user password auth_url base_url].freeze
    REQUEST_OPTIONS = %i[timeout max_retries headers].freeze
    STREAM_HEADERS = {
      "Content-Type" => "application/json", "Accept" => "text/event-stream", "Cache-Control" => "no-store"
    }.freeze

    attr_reader :config

    def initialize(**options)
      setup(Configuration.resolve(options))
    end

    # A copy with some options changed. It reuses the cached access token unless an auth option changes.
    def with_options(**overrides)
      overrides = overrides.compact
      config = Configuration.new(@config.to_h.merge(overrides))
      token_manager = @token_manager unless overrides.keys.intersect?(AUTH_OPTIONS)
      self.class.allocate.tap { it.send(:setup, config, token_manager:) }
    end

    # Forces authentication; nil when only mTLS is configured.
    def token = @token_manager.token

    def balance(request_options: {})
      request(method: :get, path: "balance", type: Types::Balance, request_options:)
    end

    def tokens_count(input:, model: nil, request_options: {})
      body = { model: config.resolve_model(model), input: Array(input) }
      request(method: :post, path: "tokens/count", body:, type: Types::TokensCountList, request_options:)
    end

    def ai_check(input:, model:, request_options: {})
      request(method: :post, path: "ai/check", body: { input:, model: }, type: Types::AiCheckResult, request_options:)
    end

    def chat = @chat ||= Resources::Chat.new(self)

    def embeddings = @embeddings ||= Resources::Embeddings.new(self)

    def models = @models ||= Resources::Models.new(self)

    def functions = @functions ||= Resources::Functions.new(self)

    def files = @files ||= Resources::Files.new(self)

    def batches = @batches ||= Resources::Batches.new(self)

    # @api private
    def chat_v2_url = @transport.chat_v2_url

    # @api private
    # Streaming POST (HTTP/2, see Internal::Transport#stream) that yields raw SSE bytes and response
    # headers. Retries and the 401 replay happen only until the first byte reaches the caller, so output is
    # never duplicated; exceptions from the block surface unchanged.
    def request_stream(path:, body:, request_options: {}, &on_chunk)
      options = check_request_options(request_options)
      headers = STREAM_HEADERS.merge(options[:headers] || {})
      payload = JSON.generate(body)
      delivered = false
      fresh = -> { !delivered }
      retry_policy(options).run(method: :post, retry_if: fresh) do
        authenticated(headers, replay: fresh) do |signed|
          stream_once(path, payload, signed, options) do |chunk, response_headers|
            delivered = true
            on_chunk.call(chunk, response_headers)
          end
        end
      end
    end

    # Low-level call with auth, retries and error mapping; also the escape hatch for undocumented endpoints.
    # Hash/Array bodies are sent as JSON and `form:` as multipart. A JSON array response is wrapped as
    # `{ data: [...] }` before building `type`; `binary: true` returns the raw body as a binary String.
    def request(method:, path:, query: nil, body: nil, form: nil, headers: {}, type: nil, binary: false,
                request_options: {})
      options = check_request_options(request_options)
      payload, request_headers = encode(body, form, headers.merge(options[:headers] || {}))
      response = execute(method:, url: path, query:, body: payload, headers: request_headers, options:,
                         ios: upload_ios(form))
      build_result(response, type, binary)
    end

    def inspect = "#<#{self.class.name} base_url=#{config.base_url.inspect} model=#{config.model.inspect}>"

    private

    def setup(config, token_manager: nil)
      @config = config
      @transport = Internal::Transport.new(config)
      @token_manager = token_manager || Auth::TokenManager.new(config, @transport)
    end

    def check_request_options(options)
      unknown = options.keys - REQUEST_OPTIONS
      raise ArgumentError, "Unknown request option(s): #{unknown.join(", ")}" if unknown.any?

      options
    end

    def encode(body, form, headers)
      base = { "Accept" => "application/json" }
      return [form, base.merge(headers)] if form
      return [body, base.merge(headers)] unless body.is_a?(Hash) || body.is_a?(Array)

      [JSON.generate(body), base.merge("Content-Type" => "application/json").merge(headers)]
    end

    def upload_ios(form)
      return [] unless form

      form.values.filter_map { it.io if it.respond_to?(:io) }
    end

    # Retry loop (outer) -> one 401 replay with a fresh token (inner) -> HTTP call.
    def execute(method:, url:, query:, body:, headers:, options:, ios: [])
      replayable = ios.all? { rewindable?(it) }
      sends = 0
      retry_policy(options).run(method:, replayable:) do
        authenticated(headers, replay: -> { replayable }) do |signed|
          ios.each(&:rewind) if (sends += 1) > 1
          response = perform(method:, url:, query:, body:, headers: signed, options:)
          next response if response.success?

          raise APIError.for(status: response.status, body: Internal::Util.parse_json(response.body),
                             headers: response.headers)
        end
      end
    end

    # Request headers merge after the token so a per-request Authorization wins (spec §4).
    def authenticated(headers, replay:)
      token = @token_manager.token
      yield authorization(token).merge(headers)
    rescue AuthenticationError => e
      raise unless e.status == 401 && token && @token_manager.refreshable? && replay.call

      @token_manager.invalidate!(token)
      yield authorization(@token_manager.token).merge(headers)
    end

    def authorization(token) = token ? { "Authorization" => "Bearer #{token.access_token}" } : {}

    # The head arrives before any body, so a non-2xx or non-SSE response is buffered and raised here, while
    # the retry and the 401 replay may still resend the request.
    def stream_once(path, payload, headers, options)
      status = nil
      response_headers = nil
      error_body = +"".b
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @transport.stream(path, body: payload, headers:, timeout: options[:timeout]) do |event, *args|
        if event == :head
          status, response_headers = args
        elsif sse?(status, response_headers)
          yield args.first, response_headers
        else
          error_body << args.first.b
        end
      end
      raise_stream_failure(status, response_headers, error_body) unless sse?(status, response_headers)
    ensure
      # Logged here so a stream that stops early (the caller breaks or [DONE] ends it) is logged too.
      log(:post, path, status, response_headers, started) if status
    end

    def sse?(status, headers) = status&.between?(200, 299) && event_stream?(headers)

    def event_stream?(headers) = headers["content-type"].to_s.start_with?("text/event-stream")

    def raise_stream_failure(status, headers, error_body)
      body = Internal::Util.parse_json(error_body)
      raise APIError.for(status:, body:, headers:) unless status.between?(200, 299)

      raise APIError.new(status:, body:, headers:,
                         message: "Expected text/event-stream, got #{headers["content-type"].inspect}")
    end

    def perform(method:, url:, headers:, options:, query: nil, body: nil, on_data: nil)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = Internal::Transport.wrap_errors do
        @transport.api.run_request(method, url, body, headers) do |req|
          query&.each { |key, value| req.params[key.to_s] = value }
          req.options.timeout = options[:timeout] if options[:timeout]
          req.options.on_data = on_data if on_data
        end
      end
      log(method, url, response.status, response.headers, started)
      response
    end

    def build_result(response, type, binary)
      return response.body.to_s.b if binary

      parsed = Internal::Util.parse_json(response.body)
      return parsed unless type

      parsed = { data: parsed } if parsed.is_a?(Array)
      unless parsed.is_a?(Hash)
        raise APIError.new(status: response.status, body: parsed, headers: response.headers,
                           message: "Unexpected non-JSON response")
      end

      type.new(parsed, x_headers: Internal::Transport.x_headers(response.headers))
    end

    def retry_policy(options)
      Internal::RetryPolicy.new(max_retries: options.fetch(:max_retries, config.max_retries), logger: config.logger)
    end

    # Pipes and sockets cannot seek back, so a retry would resend a half-read body.
    def rewindable?(io)
      io.respond_to?(:rewind) && io.respond_to?(:pos) && io.pos.is_a?(Integer)
    rescue IOError, SystemCallError
      false
    end

    def log(method, url, status, headers, started)
      return unless config.logger

      elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      config.logger.info("GigaChat: #{method.to_s.upcase} #{url} #{status} #{elapsed}ms " \
                         "req=#{headers["x-request-id"]}")
    end
  end
end
