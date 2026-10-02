# frozen_string_literal: true

module GigaChat
  module Types
    class ModelList < Base
      enumerable :data, Model
      attribute :object
    end
  end
end
