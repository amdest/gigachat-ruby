# frozen_string_literal: true

module GigaChat
  # A lazily performed chat stream. The HTTP request starts on the first #each; the stream is single-use.
  # Breaking out of #each closes the connection; #response returns what was accumulated so far.
  class Stream
    include Enumerable

    def initialize(protocol:, &requester)
      @protocol = protocol
      @requester = requester
      @accumulator = protocol == :v2 ? Internal::ChatAccumulator.new : Internal::V1ChatAccumulator.new
      @state = :pending
      @x_headers = {}
    end

    def each(&block)
      return enum_for(:each) unless block
      raise Error, "Stream has already been consumed" unless @state == :pending

      @state = :streaming
      consume(&block)
      @state = :finished
      self
    end

    def text
      return enum_for(:text) unless block_given?

      each do |event|
        piece = event.text
        yield piece unless piece.empty?
      end
    end

    def response
      each { nil } if @state == :pending
      @accumulator.result(x_headers: @x_headers)
    end

    private

    def consume(&)
      decoder = Internal::SSEDecoder.new
      catch(:done) do
        @requester.call do |chunk, headers|
          @x_headers = Internal::Transport.x_headers(headers) if headers && @x_headers.empty?
          decoder.feed(chunk) { |sse| handle(sse, &) }
        end
        decoder.finish { |sse| handle(sse, &) }
      end
    end

    def handle(sse)
      raise_error(sse) if sse.event == "error"
      return unless (event = parse(sse))

      @accumulator << event
      yield event
      throw :done if event.is_a?(Types::ChatEvent) && event.done?
    end

    def parse(sse)
      if @protocol == :v1
        throw :done if sse.data == "[DONE]"
        Types::V1::ChatCompletionChunk.new(decode(sse))
      else
        Types::ChatEvent.new(decode(sse), type: sse.event)
      end
    end

    def decode(sse)
      JSON.parse(sse.data, symbolize_names: true)
    rescue JSON::ParserError
      raise APIError.new(status: 200, body: sse.data, headers: @x_headers,
                         message: "Malformed stream event: #{sse.data[0, 200]}")
    end

    def raise_error(sse)
      body = Internal::Util.parse_json(sse.data)
      status = body.is_a?(Hash) && body[:status].is_a?(Integer) ? body[:status] : 500
      raise APIError.for(status:, body:, headers: @x_headers)
    end
  end
end
