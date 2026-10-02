# frozen_string_literal: true

module GigaChat
  module Types
    module V1
      # One `data:` frame of a v1 stream.
      class ChatCompletionChunk < Base
        attribute :choices, Choice, array: true
        attribute :created
        attribute :model
        attribute :object
        attribute :usage, Usage

        def text = (choices || []).filter_map { it.delta&.content }.join
      end
    end
  end
end
