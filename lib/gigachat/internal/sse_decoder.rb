# frozen_string_literal: true

module GigaChat
  module Internal
    # Incremental Server-Sent Events parser (WHATWG). It buffers raw bytes and decodes UTF-8 only on
    # complete lines, so Cyrillic split across TCP chunks survives.
    class SSEDecoder
      Event = Data.define(:event, :data, :id)

      BOM = "\xEF\xBB\xBF".b.freeze
      CR = 13
      LF = 10

      def initialize
        @buffer = +"".b
        @data = []
        @event = nil
        @id = nil
        @bom_checked = false
      end

      def feed(chunk, &)
        @buffer << chunk.b
        strip_bom
        while (line = next_line(final: false))
          process(line, &)
        end
      end

      def finish(&)
        while (line = next_line(final: true))
          process(line, &)
        end
        process(utf8(@buffer), &) unless @buffer.empty?
        @buffer = +"".b
        dispatch(&)
      end

      private

      def strip_bom
        return if @bom_checked || @buffer.bytesize < BOM.bytesize

        @buffer = @buffer.byteslice(BOM.bytesize..) if @buffer.start_with?(BOM)
        @bom_checked = true
      end

      # A lone trailing "\r" may be the first half of "\r\n", so wait for more bytes unless finishing.
      def next_line(final:)
        return unless (index = @buffer.index(/[\r\n]/n))

        width = 1
        if @buffer.getbyte(index) == CR
          return if index == @buffer.bytesize - 1 && !final

          width = 2 if @buffer.getbyte(index + 1) == LF
        end
        line = @buffer.byteslice(0, index)
        @buffer = @buffer.byteslice((index + width)..)
        utf8(line)
      end

      def utf8(bytes) = bytes.dup.force_encoding(Encoding::UTF_8)

      def process(line, &)
        return dispatch(&) if line.empty?
        return if line.start_with?(":")

        field, value = line.split(":", 2)
        value = value.to_s.delete_prefix(" ")
        case field
        when "event" then @event = value
        when "data" then @data << value
        when "id" then @id = value
        end
      end

      def dispatch
        yield Event.new(event: @event, data: @data.join("\n"), id: @id) unless @data.empty?
        @event = nil
        @data = []
      end
    end
  end
end
