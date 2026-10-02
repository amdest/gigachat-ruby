# frozen_string_literal: true

module GigaChat
  module Types
    class Message < Base
      attribute :role
      attribute :message_id
      attribute :content, ContentPart, array: true

      # The live API returns `tool_state_id` (checked 2026-10-02, and the request schema agrees), while the
      # spec's response schema and the Python SDK say `tools_state_id`. Read either; the raw key is kept as
      # is, so passing the message back sends exactly what the API returned.
      def tools_state_id = self[:tools_state_id] || self[:tool_state_id]

      alias tool_state_id tools_state_id

      def text = (content || []).filter_map(&:text).join
    end
  end
end
