# frozen_string_literal: true

module GigaChat
  module Resources
    # Chat completions v1 (POST /chat/completions). Fully supported, not deprecated.
    class ChatV1 < Base
      PATH = "chat/completions"

      def create(messages:, model: nil, request_options: {}, **params)
        reject_stream_flag!(params)
        @client.request(method: :post, path: PATH, body: body(messages, model, params),
                        type: Types::V1::ChatCompletion, request_options:)
      end

      def stream(messages:, model: nil, request_options: {}, **params, &)
        build_stream(protocol: :v1, path: PATH, body: body(messages, model, params), request_options:, &)
      end

      private

      def body(messages, model, params) = { model: @client.config.resolve_model(model), messages:, **params }
    end
  end
end
