# frozen_string_literal: true

module GigaChat
  module Internal
    module Util
      module_function

      # Parses JSON into symbol-keyed data. Proxies and gateways return HTML or empty bodies on errors,
      # so anything that is not JSON comes back as the (UTF-8) text itself.
      def parse_json(text)
        string = text.to_s.dup.force_encoding(Encoding::UTF_8)
        return string if string.strip.empty?

        JSON.parse(string, symbolize_names: true)
      rescue JSON::ParserError
        string
      end
    end
  end
end
