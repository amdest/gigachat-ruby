# frozen_string_literal: true

module GigaChat
  module Resources
    class Models < Base
      def list(request_options: {})
        @client.request(method: :get, path: "models", type: Types::ModelList, request_options:)
      end

      def retrieve(id, request_options: {})
        @client.request(method: :get, path: "models/#{escape(id)}", type: Types::Model, request_options:)
      end
    end
  end
end
