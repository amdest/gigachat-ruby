# frozen_string_literal: true

require "logger"
require "test_helper"

class ClientTest < GigaChatTestCase
  def test_sends_bearer_token_and_returns_typed_result
    stub_oauth
    stub_request(:get, "#{API}/balance").to_return(json_response({ balance: [{ usage: "GigaChat", value: 100_500 }] }))

    balance = build_client.balance

    assert_equal 100_500, balance.first.value
    assert_equal "req-1", balance.request_id
    assert_requested(:get, "#{API}/balance") do |req|
      req.headers["Authorization"] == "Bearer test-token" && req.headers["Accept"] == "application/json"
    end
  end

  def test_replays_once_after_401_with_a_fresh_token
    stub_request(:post, AUTH).to_return(json_response({ access_token: "old", expires_at: future_ms }),
                                        json_response({ access_token: "new", expires_at: future_ms }))
    stub_request(:get, "#{API}/balance").with(headers: { "Authorization" => "Bearer old" })
                                        .to_return(json_response({ message: "Token has expired" }, status: 401))
    stub_request(:get, "#{API}/balance").with(headers: { "Authorization" => "Bearer new" })
                                        .to_return(json_response({ balance: [] }))

    build_client.balance

    assert_requested(:post, AUTH, times: 2)
  end

  def test_second_401_is_raised
    stub_oauth
    stub_request(:get, "#{API}/balance").to_return(json_response({ message: "Unauthorized" }, status: 401))

    assert_raises(GigaChat::AuthenticationError) { build_client.balance }
    assert_requested(:get, "#{API}/balance", times: 2)
  end

  def test_static_token_401_is_not_replayed
    stub_request(:get, "#{API}/balance").to_return(json_response({ message: "Unauthorized" }, status: 401))

    assert_raises(GigaChat::AuthenticationError) { GigaChat::Client.new(access_token: "static").balance }
    assert_requested(:get, "#{API}/balance", times: 1)
  end

  def test_retries_server_errors
    stub_oauth
    stub_request(:get, "#{API}/balance").to_return(json_response({ message: "busy" }, status: 503))
                                        .then.to_return(json_response({ balance: [] }))

    build_client.balance

    assert_requested(:get, "#{API}/balance", times: 2)
    assert_equal 1, @slept.size
  end

  def test_connection_failures_are_retried_then_raised
    stub_oauth
    stub_request(:get, "#{API}/balance").to_raise(Errno::ECONNREFUSED)

    assert_raises(GigaChat::APIConnectionError) { build_client.balance }
    assert_requested(:get, "#{API}/balance", times: 3)
  end

  def test_non_json_and_empty_error_bodies_become_typed_errors
    stub_oauth
    stub_request(:get, "#{API}/balance").to_return(status: 502, body: "<html><body>Bad Gateway</body></html>",
                                                   headers: { "Content-Type" => "text/html" })
    stub_request(:get, "#{API}/models").to_return(status: 403, body: "")

    error = assert_raises(GigaChat::ServerError) { build_client(max_retries: 0).balance }
    assert_match(/Bad Gateway/, error.message)
    error = assert_raises(GigaChat::PermissionDeniedError) { build_client.request(method: :get, path: "models") }
    assert_equal "403", error.message
  end

  def test_tokens_count_wraps_the_array_response
    stub_oauth
    stub_request(:post, "#{API}/tokens/count")
      .to_return(json_response([{ object: "tokens", tokens: 7, characters: 36 }]))

    result = build_client(model: "GigaChat-2").tokens_count(input: "Я к вам пишу")

    assert_equal [7], result.map(&:tokens)
    assert_requested(:post, "#{API}/tokens/count", body: { model: "GigaChat-2", input: ["Я к вам пишу"] })
  end

  def test_tokens_count_requires_a_model
    assert_raises(GigaChat::ModelNotSpecifiedError) { build_client.tokens_count(input: "x") }
  end

  def test_ai_check
    stub_oauth
    stub_request(:post, "#{API}/ai/check").with(body: { input: "текст", model: "GigaCheckClassification" })
                                          .to_return(json_response({ category: "mixed", ai_intervals: [[0, 10]] }))

    assert_predicate build_client.ai_check(input: "текст", model: "GigaCheckClassification"), :mixed?
  end

  def test_per_request_headers_override_authorization
    stub_oauth
    stub_request(:get, "#{API}/balance").to_return(json_response({ balance: [] }))

    build_client.balance(request_options: { headers: { "Authorization" => "Bearer per-request" } })

    assert_requested(:get, "#{API}/balance") { |req| req.headers["Authorization"] == "Bearer per-request" }
  end

  def test_request_options_override_headers_and_reject_unknown_keys
    stub_oauth
    stub_request(:get, "#{API}/balance").with(headers: { "X-Client-ID" => "user-7" })
                                        .to_return(json_response({ balance: [] }))

    build_client.balance(request_options: { headers: { "X-Client-ID" => "user-7" }, timeout: 5 })

    assert_requested(:get, "#{API}/balance")
    assert_raises(ArgumentError) { build_client.balance(request_options: { retries: 1 }) }
  end

  def test_with_options_shares_the_token_and_changes_headers
    stub_oauth
    stub_request(:get, "#{API}/balance").to_return(json_response({ balance: [] }))
    client = build_client

    client.balance
    client.with_options(session_id: "s-1").balance

    assert_requested(:post, AUTH, times: 1)
    assert_requested(:get, "#{API}/balance") { |req| req.headers["X-Session-Id"] == "s-1" }
  end

  def test_base_url_with_api_prefix
    stub_oauth
    stub_request(:get, "https://gigachat.devices.sberbank.ru/api/v1/balance").to_return(json_response({ balance: [] }))

    build_client(base_url: "https://gigachat.devices.sberbank.ru/api/v1").balance

    assert_requested(:get, "https://gigachat.devices.sberbank.ru/api/v1/balance")
  end

  def test_logs_one_line_per_request_without_secrets
    stub_oauth
    stub_request(:get, "#{API}/balance").to_return(json_response({ balance: [] }))
    log = StringIO.new

    build_client(logger: Logger.new(log)).balance

    assert_match(/GET balance 200 \d+ms req=req-1/, log.string)
    refute_includes log.string, "test-token"
    refute_includes log.string, CREDENTIALS
  end

  def test_inspect_hides_credentials_and_token_is_public
    stub_oauth
    client = build_client

    refute_includes client.inspect, CREDENTIALS
    assert_equal "test-token", client.token.access_token
  end

  def test_non_utf8_error_body_becomes_a_typed_error
    stub_oauth
    page = "<html>Ошибка шлюза</html>".encode("Windows-1251").b
    stub_request(:get, "#{API}/balance")
      .to_return(status: 502, body: page, headers: { "Content-Type" => "text/html; charset=windows-1251" })

    error = assert_raises(GigaChat::ServerError) { build_client(max_retries: 0).balance }
    assert_equal 502, error.status
  end
end
