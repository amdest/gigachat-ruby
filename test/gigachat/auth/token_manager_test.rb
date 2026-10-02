# frozen_string_literal: true

require "pp"
require "test_helper"

class TokenManagerTest < GigaChatTestCase
  def manager(**options)
    config = GigaChat::Configuration.resolve(options)
    GigaChat::Auth::TokenManager.new(config, GigaChat::Internal::Transport.new(config))
  end

  def test_oauth_request_shape
    stub_oauth

    token = manager(credentials: CREDENTIALS, scope: "GIGACHAT_API_CORP").token

    assert_equal "test-token", token.access_token
    assert_requested(:post, AUTH, times: 1) do |req|
      req.headers["Authorization"] == "Basic #{CREDENTIALS}" && req.headers["Rquid"].match?(UUID) &&
        req.headers["Content-Type"] == "application/x-www-form-urlencoded" && req.body == "scope=GIGACHAT_API_CORP"
    end
  end

  def test_token_is_cached_outside_the_expiry_buffer
    stub_oauth
    tokens = manager(credentials: CREDENTIALS)

    2.times { tokens.token }

    assert_requested(:post, AUTH, times: 1)
  end

  def test_token_is_refreshed_inside_the_expiry_buffer
    stub_oauth(expires_at: future_ms(30))
    tokens = manager(credentials: CREDENTIALS)

    2.times { tokens.token }

    assert_requested(:post, AUTH, times: 2)
  end

  def test_tok_exp_shape_in_seconds_is_normalized
    stub_request(:post, AUTH).to_return(json_response({ tok: "t", exp: Time.now.to_i + 1800 }))

    token = manager(credentials: CREDENTIALS).token

    assert_equal "t", token.access_token
    assert_operator token.expires_at, :>, 1_000_000_000_000, "seconds must be converted to milliseconds"
  end

  def test_static_access_token_never_expires_locally
    token = manager(access_token: "static").token

    assert_equal "static", token.access_token
    assert_equal 0, token.expires_at
    assert_not_requested(:post, AUTH)
  end

  def test_pasted_credentials_are_cleaned
    stub_oauth

    manager(credentials: "  Basic #{CREDENTIALS}\n").token

    assert_requested(:post, AUTH) { |req| req.headers["Authorization"] == "Basic #{CREDENTIALS}" }
  end

  def test_oauth_client_errors_raise_authentication_error
    stub_request(:post, AUTH).to_return(json_response({ code: 6, message: "credentials doesn't match db data" },
                                                      status: 401))

    error = assert_raises(GigaChat::AuthenticationError) { manager(credentials: CREDENTIALS).token }
    assert_match(/credentials doesn't match/, error.message)
  end

  def test_oauth_server_errors_stay_retryable
    stub_request(:post, AUTH).to_return(json_response({ message: "down" }, status: 503))

    assert_raises(GigaChat::ServerError) { manager(credentials: CREDENTIALS).token }
  end

  def test_password_flow_uses_basic_auth_on_token_endpoint
    stub_request(:post, "#{API}/token").to_return(json_response({ tok: "pw-token", exp: future_ms }))

    token = manager(user: "u", password: "p").token

    assert_equal "pw-token", token.access_token
    assert_requested(:post, "#{API}/token") { |req| req.headers["Authorization"] == "Basic #{["u:p"].pack("m0")}" }
  end

  def test_missing_auth_raises_configuration_error
    assert_raises(GigaChat::ConfigurationError) { manager.token }
  end

  def test_mtls_only_needs_no_token
    assert_nil manager(cert_file: "/path/to/cert.pem").token
  end

  def test_concurrent_first_calls_fetch_once
    stub_oauth
    tokens = manager(credentials: CREDENTIALS)

    Array.new(8) { Thread.new { tokens.token } }.each(&:join)

    assert_requested(:post, AUTH, times: 1)
  end

  def test_invalidate_drops_only_the_stale_token
    stub_oauth
    tokens = manager(credentials: CREDENTIALS)
    stale = tokens.token

    tokens.invalidate!(stale)
    tokens.token

    assert_requested(:post, AUTH, times: 2)
  end

  def test_access_token_inspect_masks_the_secret
    refute_match(/SECRET/, GigaChat::Auth::AccessToken.new(access_token: "SECRET", expires_at: 0).inspect)
  end

  def test_token_manager_and_access_token_never_print_secrets
    stub_oauth(token: "TOKEN-SECRET")
    tokens = manager(credentials: "CRED-SECRET")
    token = tokens.token

    [tokens.inspect, tokens.pretty_inspect, token.inspect, token.pretty_inspect].each do |text|
      refute_match(/SECRET/, text)
    end
  end

  def test_wrapped_and_lowercase_credentials_are_cleaned
    stub_oauth

    manager(credentials: "basic #{CREDENTIALS[0, 16]}\n#{CREDENTIALS[16..]}").token

    assert_requested(:post, AUTH) { |req| req.headers["Authorization"] == "Basic #{CREDENTIALS}" }
  end

  def test_token_survives_a_concurrent_invalidation
    stub_oauth
    tokens = manager(credentials: CREDENTIALS)
    tokens.token
    # Another thread invalidating the token between the usability check and the return.
    tokens.define_singleton_method(:usable?) { |token| super(token).tap { @token = nil } }

    refute_nil tokens.token, "a token checked as usable must be the one returned"
  end
end
