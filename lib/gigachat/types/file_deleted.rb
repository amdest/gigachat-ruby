# frozen_string_literal: true

module GigaChat
  module Types
    class FileDeleted < Base
      attribute :id
      attribute :deleted
      attribute :access_policy

      def deleted? = deleted == true
    end
  end
end
