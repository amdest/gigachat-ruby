# frozen_string_literal: true

module GigaChat
  module Types
    class Message < Base
      attribute :role
      attribute :message_id
      attribute :tools_state_id
      attribute :content, ContentPart, array: true

      def text = (content || []).filter_map(&:text).join
    end
  end
end
