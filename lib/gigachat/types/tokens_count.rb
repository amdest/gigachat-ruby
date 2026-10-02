# frozen_string_literal: true

module GigaChat
  module Types
    class TokensCount < Base
      attribute :object
      attribute :tokens
      attribute :characters
    end
  end
end
