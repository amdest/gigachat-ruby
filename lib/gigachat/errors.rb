# frozen_string_literal: true

module GigaChat
  class Error < StandardError; end

  class ConfigurationError < Error; end

  class ModelNotSpecifiedError < Error; end

  class APIConnectionError < Error
    def initialize(message = "Connection error") = super
  end

  class APITimeoutError < APIConnectionError
    def initialize(message = "Request timed out") = super
  end

  # Non-2xx response. `body` is parsed JSON (symbol keys) when possible, otherwise the raw text.
  class APIError < Error
    attr_reader :status, :body, :headers

    def self.for(status:, body: nil, headers: {})
      error_class(status).new(status:, body:, headers:)
    end

    def self.error_class(status)
      return ServerError if status >= 500

      {
        400 => BadRequestError, 401 => AuthenticationError, 403 => PermissionDeniedError,
        404 => NotFoundError, 413 => RequestEntityTooLargeError, 422 => UnprocessableEntityError,
        429 => RateLimitError
      }.fetch(status, APIError)
    end

    def initialize(status:, body: nil, headers: {}, message: nil)
      @status = status
      @body = body
      @headers = headers || {}
      super(message || default_message)
    end

    def request_id = headers["x-request-id"]

    private

    def default_message
      request = "(request_id: #{request_id})" if request_id
      [status, detail, request].reject { it.nil? || it.to_s.empty? }.join(" ")
    end

    # The documented `message`, else the body itself (compact JSON or text), squashed to one short line.
    def detail
      text = body.is_a?(Hash) ? body[:message] || JSON.generate(body) : body.to_s
      text.to_s.strip.gsub(/\s+/, " ")[0, 200]
    end
  end

  class BadRequestError < APIError; end

  class AuthenticationError < APIError; end

  class PermissionDeniedError < APIError; end

  class NotFoundError < APIError; end

  class RequestEntityTooLargeError < APIError; end

  class UnprocessableEntityError < APIError; end

  class RateLimitError < APIError
    # Seconds the server asked us to wait (Retry-After), or nil.
    def retry_after = Internal::RetryPolicy.retry_after(headers)
  end

  class ServerError < APIError; end
end
