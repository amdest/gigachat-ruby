# frozen_string_literal: true

module GigaChat
  module Internal
    # Decides whether a failed request is retried and how long to wait first.
    class RetryPolicy
      RETRYABLE_STATUSES = [429, 500, 502, 503, 504].freeze
      INITIAL_DELAY = 0.5
      MAX_DELAY = 8.0
      MAX_RETRY_AFTER = 60.0

      class << self
        # Injectable so tests can record delays instead of sleeping.
        attr_writer :sleeper

        def sleeper = @sleeper ||= ->(seconds) { Kernel.sleep(seconds) }

        # Seconds from a Retry-After header (delta-seconds or HTTP-date), capped; nil when absent or invalid.
        def retry_after(headers)
          value = headers && headers["retry-after"]
          return if value.nil? || value.to_s.strip.empty?

          seconds = Float(value, exception: false) || (Time.httpdate(value.to_s) - Time.now)
          seconds.clamp(0.0, MAX_RETRY_AFTER)
        rescue ArgumentError
          nil
        end
      end

      def initialize(max_retries:, logger: nil)
        @max_retries = max_retries.to_i
        @logger = logger
      end

      def run(method:, replayable: true, retry_if: nil)
        attempt = 0
        begin
          yield
        rescue APIError, APIConnectionError => e
          raise unless attempt < @max_retries && replayable && (retry_if.nil? || retry_if.call)
          raise unless retryable?(e, method)

          delay = delay_for(e, attempt)
          @logger&.debug("GigaChat: retry #{attempt + 1}/#{@max_retries} in #{delay.round(2)}s after #{e.class}")
          self.class.sleeper.call(delay)
          attempt += 1
          retry
        end
      end

      private

      def retryable?(error, method)
        case error
        when APITimeoutError then method.to_s.casecmp?("get") # a timed-out POST may already be billed
        when APIConnectionError then Transport.retryable_connection_error?(error.cause) # never retry TLS errors
        else RETRYABLE_STATUSES.include?(error.status)
        end
      end

      def delay_for(error, attempt)
        server = self.class.retry_after(error.headers) if error.is_a?(APIError)
        server || ((INITIAL_DELAY * (2**attempt)).clamp(0.0, MAX_DELAY) * (1 - (0.25 * rand)))
      end
    end
  end
end
