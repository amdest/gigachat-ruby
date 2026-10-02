# frozen_string_literal: true

module GigaChat
  module Types
    class ToolExecution < Base
      attribute :name
      attribute :status
      attribute :seconds_left
      attribute :censored
    end
  end
end
