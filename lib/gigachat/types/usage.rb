# frozen_string_literal: true

module GigaChat
  module Types
    class Usage < Base
      attribute :input_tokens
      attribute :input_tokens_details
      attribute :output_tokens
      attribute :total_tokens
    end
  end
end
