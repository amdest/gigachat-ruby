# frozen_string_literal: true

module GigaChat
  module Types
    class Batch < Base
      class RequestCounts < Base
        attribute :total
        attribute :completed
        attribute :failed
      end

      attribute :id
      attribute :request_counts, RequestCounts
      attribute :status
      attribute :output_file_id
      attribute :created_at
      attribute :updated_at

      # A `method` reader would shadow Object#method; the raw value stays available via `[:method]`.
      def batch_method = self[:method]

      def created? = status == "created"

      def in_progress? = status == "in_progress"

      def completed? = status == "completed"
    end
  end
end
