# frozen_string_literal: true

module GigaChat
  module Internal
    # Folds v2 stream events into one ChatCompletion: text parts are concatenated per message position,
    # other parts (function calls, files, ...) are appended, and the last non-nil metadata wins.
    class ChatAccumulator
      META = %i[model created_at created thread_id message_id finish_reason usage additional_data].freeze
      # Per-message fields; both state id spellings are kept as sent (see Types::Message#tools_state_id).
      MESSAGE_KEYS = %i[role message_id tool_state_id tools_state_id].freeze

      def initialize
        @meta = {}
        @messages = []
      end

      def <<(event)
        return self if event.tool_in_progress? # progress ticks, not content

        @meta.merge!(event.to_h.slice(*META).compact)
        (event.messages || []).each_with_index { |message, index| merge_message(index, message) }
        self
      end

      def result(x_headers: {})
        Types::ChatCompletion.new({ **@meta, messages: @messages.compact.map { finalize(it) } }, x_headers:)
      end

      private

      def merge_message(index, message)
        entry = @messages[index] ||= { text: +"", parts: [] }
        MESSAGE_KEYS.each { |key| entry[key] = message[key] if message[key] }
        (message.content || []).each do |part|
          entry[:text] << part.text if part.text
          rest = part.to_h.except(:text)
          entry[:parts] << rest unless rest.empty?
        end
      end

      def finalize(entry)
        content = entry[:text].empty? ? entry[:parts] : [{ text: entry[:text] }, *entry[:parts]]
        entry.slice(*MESSAGE_KEYS).merge(content:)
      end
    end
  end
end
