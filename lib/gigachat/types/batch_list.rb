# frozen_string_literal: true

module GigaChat
  module Types
    # GET /batches. The spec documents `{ batches: [...] }`; the JS SDK assumes a bare array, which the
    # client wraps as `{ data: [...] }`. Both shapes enumerate the same way.
    class BatchList < Base
      include Enumerable

      def batches = @batches ||= (self[:batches] || self[:data] || []).map { Batch.coerce(it) }

      def each(&) = batches.each(&)

      def to_h = @data
    end
  end
end
