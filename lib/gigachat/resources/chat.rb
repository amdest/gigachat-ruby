# frozen_string_literal: true

module GigaChat
  module Resources
    # Chat completions v2 (primary API). v1 lives under #v1.
    class Chat < Base
      attr_reader :v1

      def initialize(client)
        super
        @v1 = ChatV1.new(client)
      end

      def create(messages:, model: nil, request_options: {}, **params)
        reject_stream_flag!(params)
        @client.request(method: :post, path: @client.chat_v2_url, body: body(messages, model, params),
                        type: Types::ChatCompletion, request_options:)
      end

      def stream(messages:, model: nil, request_options: {}, **params, &)
        build_stream(protocol: :v2, path: @client.chat_v2_url, body: body(messages, model, params), request_options:, &)
      end

      private

      def body(messages, model, params)
        { model: @client.config.resolve_model(model), messages: messages.map { normalize(it) }, **params }
      end

      # v2 content is an array of parts; accept the familiar `content: "text"` shorthand.
      def normalize(message)
        return message unless message.is_a?(Hash)

        key = message.key?(:content) ? :content : "content"
        case message[key]
        when String then message.merge(key => [{ text: message[key] }])
        when Hash then message.merge(key => [message[key]])
        else message
        end
      end
    end
  end
end
