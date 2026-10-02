# frozen_string_literal: true

module GigaChat
  module Resources
    class Embeddings < Base
      # The chat model from config does not apply here; "Embeddings" matches both official SDKs.
      def create(input:, model: "Embeddings", request_options: {}, **params)
        @client.request(method: :post, path: "embeddings", body: { model:, input:, **params },
                        type: Types::Embeddings, request_options:)
      end
    end
  end
end
