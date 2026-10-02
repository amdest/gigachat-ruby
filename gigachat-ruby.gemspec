# frozen_string_literal: true

require_relative "lib/gigachat/version"

Gem::Specification.new do |spec|
  spec.name = "gigachat-ruby"
  spec.version = GigaChat::VERSION
  spec.authors = ["Aleksandr Dryzhuk"]
  spec.email = ["dev@ad-it.pro"]

  spec.summary = "Ruby client for the GigaChat REST API"
  spec.description = "Plain-Ruby client for Sber's GigaChat API: chat (v2 and v1) with SSE streaming, " \
                     "embeddings, files, batches, token counting and AI-text detection."
  spec.homepage = "https://github.com/amdest/gigachat-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/master/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*", "README.md", "CHANGELOG.md", "LICENSE.txt"]
  spec.require_paths = ["lib"]

  spec.add_dependency "faraday", "~> 2.14"
  spec.add_dependency "faraday-multipart", "~> 1.2"
  spec.add_dependency "zeitwerk", "~> 2.8"
end
