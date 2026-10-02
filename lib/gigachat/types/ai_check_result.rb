# frozen_string_literal: true

module GigaChat
  module Types
    class AiCheckResult < Base
      attribute :category
      attribute :characters
      attribute :tokens
      attribute :ai_intervals

      def ai? = category == "ai"

      def human? = category == "human"

      def mixed? = category == "mixed"
    end
  end
end
