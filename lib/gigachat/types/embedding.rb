# frozen_string_literal: true

module GigaChat
  module Types
    class Embedding < Base
      attribute :object
      attribute :embedding
      attribute :index
      attribute :usage
    end
  end
end
