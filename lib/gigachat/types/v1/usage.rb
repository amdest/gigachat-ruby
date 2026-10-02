# frozen_string_literal: true

module GigaChat
  module Types
    module V1
      class Usage < Base
        attribute :prompt_tokens
        attribute :completion_tokens
        attribute :precached_prompt_tokens
        attribute :total_tokens
      end
    end
  end
end
