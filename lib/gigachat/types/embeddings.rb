# frozen_string_literal: true

module GigaChat
  module Types
    class Embeddings < Base
      enumerable :data, Embedding
      attribute :model
      attribute :object

      def vectors = map(&:embedding)
    end
  end
end
