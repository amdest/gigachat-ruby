# frozen_string_literal: true

module GigaChat
  # Entry point to the GigaChat REST API. Thread-safe: share one instance across threads.
  class Client
    AUTH_OPTIONS = %i[credentials scope access_token user password auth_url base_url].freeze
    REQUEST_OPTIONS = %i[timeout max_retries headers].freeze

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

    def authenticated(headers, replay:)
      token = @token_manager.token
      yield headers.merge(authorization(token))
    rescue AuthenticationError => e
      raise unless e.status == 401 && token && @token_manager.refreshable? && replay.call

      @token_manager.invalidate!(token)
      yield headers.merge(authorization(@token_manager.token))
    end

    def authorization(token) = token ? { "Authorization" => "Bearer #{token.access_token}" } : {}

    def perform(method:, url:, headers:, options:, query: nil, body: nil, on_data: nil)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = Internal::Transport.wrap_errors do
        @transport.api.run_request(method, url, body, headers) do |req|
          query&.each { |key, value| req.params[key.to_s] = value }
          req.options.timeout = options[:timeout] if options[:timeout]
          req.options.on_data = on_data if on_data
        end
      end
      log(method, url, response, started)
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

    def log(method, url, response, started)
      return unless config.logger

      elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      config.logger.info("GigaChat: #{method.to_s.upcase} #{url} #{response.status} #{elapsed}ms " \
                         "req=#{response.headers["x-request-id"]}")
    end
  end
end
