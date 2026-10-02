# frozen_string_literal: true

module GigaChat
  module Types
    class FileRef < Base
      attribute :id
      attribute :target
      attribute :mime
    end
  end
end
