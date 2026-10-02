# frozen_string_literal: true

module GigaChat
  module Types
    class Balance < Base
      enumerable :balance, BalanceEntry
    end
  end
end
