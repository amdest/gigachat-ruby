# frozen_string_literal: true

module GigaChat
  module Types
    # Response of POST /v2/chat/completions.
    class ChatCompletion < Base
      attribute :model
      attribute :thread_id
      attribute :message_id
      attribute :messages, Message, array: true
      attribute :finish_reason
      attribute :usage, Usage
      attribute :additional_data

      # The spec documents `created_at`; the Python SDK also accepts `created`.
      def created_at = self[:created_at] || self[:created]

      def text = assistant_messages.map(&:text).join

      def message = assistant_messages.first

      def function_call = parts.find(&:function_call)&.function_call

      def files = parts.flat_map { it.files || [] }

      private

      def assistant_messages = (messages || []).select { [nil, "assistant"].include?(it.role) }

      def parts = (messages || []).flat_map { it.content || [] }
    end
  end
end
