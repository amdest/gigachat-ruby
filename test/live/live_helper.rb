# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require "gigachat"
require "logger"
require "minitest/autorun"

# Real API calls. Opt-in: never runs without GIGACHAT_CREDENTIALS, and never in CI by default.
class LiveTestCase < Minitest::Test
  def setup
    skip "Set GIGACHAT_CREDENTIALS to run live tests" if ENV["GIGACHAT_CREDENTIALS"].to_s.strip.empty?
    logger = Logger.new($stdout) if ENV["GIGACHAT_LIVE_LOG"]
    @client = GigaChat::Client.new(model: ENV.fetch("GIGACHAT_MODEL", "GigaChat-2"), timeout: 120, logger:)
  end

  def scope = ENV.fetch("GIGACHAT_SCOPE", "GIGACHAT_API_PERS")

  def require_scope!(*scopes)
    skip "Needs #{scopes.join(" or ")} (current: #{scope})" unless scopes.include?(scope)
  end
end
