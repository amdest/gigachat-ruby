# frozen_string_literal: true

module GigaChat
  module Types
    class FunctionCall < Base
      attribute :name

      # The spec types arguments as a JSON string, but the API (and both official SDKs) send an object.
      # Accept both and always hand back a Hash; the raw value stays available via `[:arguments]`.
      def arguments
        raw = self[:arguments]
        return raw if raw.is_a?(Hash)
        return {} unless raw.is_a?(String)

        parsed = JSON.parse(raw, symbolize_names: true)
        parsed.is_a?(Hash) ? parsed : {}
      rescue JSON::ParserError
        {}
      end
    end
  end
end
