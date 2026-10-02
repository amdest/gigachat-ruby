# frozen_string_literal: true

module GigaChat
  module Auth
    # Obtains and caches access tokens. Thread-safe: one manager serves every thread of a client.
    class TokenManager
      EXPIRY_BUFFER_MS = 60_000

      def initialize(config, transport)
        @config = config
        @transport = transport
        @credentials = clean(config.credentials)
        @mutex = Mutex.new
        @token = AccessToken.new(access_token: config.access_token, expires_at: 0) if config.access_token
      end

      # A usable token, fetched when missing or about to expire; nil when only mTLS is configured.
      def token
        current = @token # read once: another thread may invalidate! between the check and the return
        return current if usable?(current)
        return unauthenticated unless refreshable?

        @mutex.synchronize { usable?(@token) ? @token : (@token = fetch) }
      end

      def refreshable? = !@credentials.nil? || !(@config.user.nil? || @config.password.nil?)

      # Drops the token only if it is still the stale one, so a fresh token from another thread survives.
      def invalidate!(stale)
        @mutex.synchronize { @token = nil if @token.equal?(stale) }
      end

      # The default #inspect would print the long-lived credentials.
      def inspect = "#<#{self.class.name} token=#{@token ? "[FILTERED]" : "nil"}>"

      private

      def usable?(token)
        !token.nil? && (token.expires_at.zero? || token.expires_at > now_ms + EXPIRY_BUFFER_MS)
      end

      def now_ms = (Time.now.to_f * 1000).to_i

      def unauthenticated
        return if @config.cert_file

        raise ConfigurationError, "No authentication configured: set credentials, access_token, " \
                                  "user/password or cert_file"
      end

      def fetch
        response = Internal::Transport.wrap_errors { @credentials ? request_oauth : request_password }
        token = parse(response)
        @config.logger&.debug("GigaChat: access token refreshed (expires_at=#{token.expires_at})")
        token
      end

      def request_oauth
        @transport.auth.post do |req|
          req.headers["Authorization"] = "Basic #{@credentials}"
          req.headers["RqUID"] = SecureRandom.uuid
          req.headers["Accept"] = "application/json"
          req.headers["Content-Type"] = "application/x-www-form-urlencoded"
          req.body = URI.encode_www_form(scope: @config.scope)
        end
      end

      def request_password
        basic = ["#{@config.user}:#{@config.password}"].pack("m0")
        @transport.api.post("token") do |req|
          req.headers["Authorization"] = "Basic #{basic}"
          req.headers["Accept"] = "application/json"
        end
      end

      def parse(response)
        body = Internal::Util.parse_json(response.body)
        raise auth_error(response, body) unless response.success?

        data = body.is_a?(Hash) ? body : {}
        value = data[:access_token] || data[:tok]
        expires = data[:expires_at] || data[:exp]
        unless value && expires
          raise AuthenticationError.new(status: response.status, body:, headers: response.headers,
                                        message: "Unexpected token response")
        end

        AccessToken.new(access_token: value, expires_at: AccessToken.normalize_ms(Integer(expires)))
      end

      # 4xx from the auth endpoint means bad credentials or scope; 429/5xx stay retryable.
      def auth_error(response, body)
        status = response.status
        return APIError.for(status:, body:, headers: response.headers) if status == 429 || status >= 500

        AuthenticationError.new(status:, body:, headers: response.headers)
      end

      # Keys copied from the dashboard often carry a "Basic " prefix, and `base64` wraps lines at 76 columns.
      # Base64 never contains whitespace, so any of it is noise (and a CR/LF would break the header).
      def clean(credentials)
        value = credentials.to_s.sub(/\A\s*basic\s+/i, "").gsub(/\s+/, "")
        value.empty? ? nil : value
      end
    end
  end
end
