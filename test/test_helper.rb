# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "gigachat"
require "minitest/autorun"
require "tmpdir"
require "webmock/minitest"

WebMock.disable_net_connect!

# Base class for unit tests: isolates GIGACHAT_* env vars and offers HTTP stub helpers.
class GigaChatTestCase < Minitest::Test
  API = "https://api.giga.chat/v1"
  V2_CHAT = "https://api.giga.chat/v2/chat/completions"
  AUTH = "https://ngw.devices.sberbank.ru:9443/api/v2/oauth"
  CREDENTIALS = "Y2xpZW50LWlkOmNsaWVudC1zZWNyZXQ=" # base64("client-id:client-secret")
  UUID = /\A\h{8}-\h{4}-4\h{3}-[89ab]\h{3}-\h{12}\z/
  SSE_HEADERS = { "Content-Type" => "text/event-stream", "X-Request-ID" => "req-s" }.freeze

  def setup
    super
    @saved_env = ENV.to_h.select { |key, _| key.start_with?("GIGACHAT_") }
    @saved_env.each_key { ENV.delete(it) }
    GigaChat.reset_config!
    @slept = []
    GigaChat::Internal::RetryPolicy.sleeper = ->(seconds) { @slept << seconds }
  end

  def teardown
    GigaChat::Internal::RetryPolicy.sleeper = nil
    ENV.keys.grep(/\AGIGACHAT_/).each { ENV.delete(it) }
    @saved_env.each { |key, value| ENV[key] = value }
    super
  end

  def fixture(name) = File.read(File.expand_path("fixtures/#{name}", __dir__))

  def json_fixture(name) = JSON.parse(fixture(name), symbolize_names: true)

  def future_ms(seconds = 1800) = ((Time.now.to_f + seconds) * 1000).to_i

  def json_response(body, status: 200, headers: {})
    {
      status:,
      body: body.is_a?(String) ? body : JSON.generate(body),
      headers: { "Content-Type" => "application/json", "X-Request-ID" => "req-1" }.merge(headers)
    }
  end

  def build_client(**) = GigaChat::Client.new(credentials: CREDENTIALS, **)

  def stub_oauth(token: "test-token", expires_at: future_ms)
    stub_request(:post, AUTH).to_return(json_response({ access_token: token, expires_at: }))
  end
end
