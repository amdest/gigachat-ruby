# frozen_string_literal: true

module GigaChat
  module Types
    module V1
      # Response of POST /chat/completions (v1).
      class ChatCompletion < Base
        attribute :choices, Choice, array: true
        attribute :created
        attribute :model
        attribute :object
        attribute :usage, Usage

        def text = choices.to_a.first&.message&.content || ""
      end
    end
  end
end
