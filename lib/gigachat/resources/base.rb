# frozen_string_literal: true

module GigaChat
  module Resources
    # Shared plumbing for resource classes: they only build bodies and pick response types.
    class Base
      def initialize(client)
        @client = client
      end

      private

      def escape(segment) = URI.encode_uri_component(segment.to_s)

      def reject_stream_flag!(params)
        raise ArgumentError, "Use #stream for streaming; #create does not accept stream:" if params.key?(:stream)
      end

      # Block given: iterate now and return the accumulated response. No block: return the lazy stream.
      def build_stream(protocol:, path:, body:, request_options:, &block)
        stream = GigaChat::Stream.new(protocol:) do |&on_chunk|
          @client.request_stream(path:, body: body.merge(stream: true), request_options:, &on_chunk)
        end
        return stream unless block

        stream.each(&block)
        stream.response
      end
    end
  end
end
