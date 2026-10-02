# frozen_string_literal: true

module GigaChat
  module Resources
    class Functions < Base
      # Accepts a function description as a Hash, as keywords, or both (keywords win).
      def validate(function = nil, request_options: {}, **attributes)
        body = (function || {}).to_h.merge(attributes)
        @client.request(method: :post, path: "functions/validate", body:, type: Types::FunctionValidation,
                        request_options:)
      end
    end
  end
end
