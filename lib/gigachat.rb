# frozen_string_literal: true

require "faraday"
require "faraday/multipart"
require "json"
require "openssl"
require "securerandom"
require "stringio"
require "time"
require "uri"
require "zeitwerk"

# Ruby client for the GigaChat REST API.
module GigaChat
  LOADER = Zeitwerk::Loader.for_gem(warn_on_extra_files: false)
  LOADER.inflector.inflect("gigachat" => "GigaChat", "sse_decoder" => "SSEDecoder")
  # The shim's name is not a valid constant; errors.rb defines many constants and is required explicitly.
  LOADER.ignore("#{__dir__}/gigachat-ruby.rb", "#{__dir__}/gigachat/errors.rb")
  LOADER.setup
end

require_relative "gigachat/errors"
