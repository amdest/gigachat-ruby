# frozen_string_literal: true

module GigaChat
  module Types
    # POST /tokens/count returns a bare JSON array; the client wraps it as `{ data: [...] }`.
    class TokensCountList < Base
      enumerable :data, TokensCount
    end
  end
end
