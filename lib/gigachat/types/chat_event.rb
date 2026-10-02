# frozen_string_literal: true

module GigaChat
  module Types
    # One named SSE event of a v2 stream (`response.message.delta`, `response.message.done`, ...).
    class ChatEvent < ChatCompletion
      DELTA = "response.message.delta"
      DONE = "response.message.done"
      TOOL_IN_PROGRESS = "response.tool.in_progress"
      TOOL_COMPLETED = "response.tool.completed"

      attr_reader :type

      def initialize(data = {}, type: nil, x_headers: nil)
        super(data, x_headers:)
        @type = type
      end

      def delta? = type == DELTA

      def done? = type == DONE

      def tool_in_progress? = type == TOOL_IN_PROGRESS

      def tool_completed? = type == TOOL_COMPLETED
    end
  end
end
