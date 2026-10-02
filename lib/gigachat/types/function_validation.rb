# frozen_string_literal: true

module GigaChat
  module Types
    class FunctionValidation < Base
      class Issue < Base
        attribute :description
        attribute :schema_location
      end

      attribute :status
      attribute :message
      attribute :json_ai_rules_version
      attribute :errors, Issue, array: true
      attribute :warnings, Issue, array: true

      def valid? = (errors || []).empty?
    end
  end
end
