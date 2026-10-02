# frozen_string_literal: true

module GigaChat
  module Types
    module V1
      class Message < Base
        attribute :role
        attribute :content
        attribute :name
        attribute :created
        attribute :functions_state_id
        attribute :function_call, FunctionCall
      end
    end
  end
end
