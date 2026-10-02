# frozen_string_literal: true

module GigaChat
  module Resources
    # Asynchronous batch processing (pay-as-you-go/CORP only).
    class Batches < Base
      METHODS = %w[chat_completions embedder].freeze

      def create(input, method:, request_options: {})
        kind = method.to_s
        raise ArgumentError, "method: must be one of #{METHODS.join(", ")}" unless METHODS.include?(kind)

        @client.request(method: :post, path: "batches", query: { method: kind }, body: jsonl(input),
                        headers: { "Content-Type" => "application/octet-stream" }, type: Types::Batch,
                        request_options:)
      end

      def list(request_options: {})
        @client.request(method: :get, path: "batches", type: Types::BatchList, request_options:)
      end

      def retrieve(id, request_options: {})
        found = @client.request(method: :get, path: "batches", query: { batch_id: id }, type: Types::BatchList,
                                request_options:)
        return Types::Batch.new(found.to_h, x_headers: found.x_headers) if found[:id]

        found.first || raise(NotFoundError.new(status: 404, body: found.to_h, headers: found.x_headers,
                                               message: "Batch #{id} not found"))
      end

      # Downloads the batch output (JSONL) and parses one Hash per non-empty line.
      def results(batch, request_options: {})
        file_id = batch.is_a?(Types::Batch) ? batch.output_file_id : batch.to_s
        raise Error, "The batch has no output file yet" if file_id.to_s.empty?

        @client.files.content(file_id, request_options:).force_encoding(Encoding::UTF_8).each_line.filter_map do |line|
          JSON.parse(line, symbolize_names: true) unless line.strip.empty?
        end
      end

      private

      def jsonl(input)
        case input
        when Array then input.map { "#{JSON.generate(it)}\n" }.join
        when String, Pathname then File.binread(input)
        else
          raise ArgumentError, "input must be an Array of requests, a path or an IO" unless input.respond_to?(:read)

          input.read
        end
      end
    end
  end
end
