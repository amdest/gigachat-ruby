# frozen_string_literal: true

module GigaChat
  module Types
    class ContentPart < Base
      attribute :text
      attribute :files, FileRef, array: true
      attribute :function_call, FunctionCall
      attribute :function_result
      attribute :tool_execution, ToolExecution
      attribute :logprobs
      attribute :inline_data
    end
  end
end
