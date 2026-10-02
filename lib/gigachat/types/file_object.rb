# frozen_string_literal: true

module GigaChat
  module Types
    class FileObject < Base
      attribute :id
      attribute :bytes
      attribute :created_at
      attribute :filename
      attribute :object
      attribute :purpose
      attribute :access_policy
      attribute :modalities
    end
  end
end
