# frozen_string_literal: true

module GigaChat
  module Types
    module V1
      class Choice < Base
        attribute :message, Message
        attribute :delta, Message
        attribute :index
        attribute :finish_reason
      end
    end
  end
end
