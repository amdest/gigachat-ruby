# frozen_string_literal: true

module GigaChat
  module Auth
    # `expires_at` is Unix time in milliseconds; 0 means "never expires locally" (a static token).
    AccessToken = Data.define(:access_token, :expires_at) do
      # The OAuth endpoint returns milliseconds, but /token (`exp`) may return seconds.
      def self.normalize_ms(value) = value.positive? && value < 1_000_000_000_000 ? value * 1000 : value

      def inspect = "#<#{self.class.name} access_token=[FILTERED] expires_at=#{expires_at}>"

      alias_method :to_s, :inspect
    end
  end
end
