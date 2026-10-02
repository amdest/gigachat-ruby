# frozen_string_literal: true

require "test_helper"

class RetryPolicyTest < GigaChatTestCase
  def policy(max_retries: 2) = GigaChat::Internal::RetryPolicy.new(max_retries:)

  def wrapped(error_class) = GigaChat::Internal::Transport.wrap_errors { raise error_class, "boom" }

  def test_retries_retryable_statuses_then_succeeds
    attempts = 0

    result = policy.run(method: :post) do
      attempts += 1
      raise GigaChat::APIError.for(status: 503) if attempts < 3

      :ok
    end

    assert_equal :ok, result
    assert_equal 3, attempts
    assert_equal 2, @slept.size
  end

  def test_gives_up_after_max_retries
    attempts = 0

    assert_raises(GigaChat::ServerError) do
      policy(max_retries: 1).run(method: :get) do
        attempts += 1
        raise GigaChat::APIError.for(status: 500)
      end
    end
    assert_equal 2, attempts
  end

  def test_client_errors_are_not_retried
    [400, 401, 403, 404, 422].each do |status|
      attempts = 0

      assert_raises(GigaChat::APIError) do
        policy.run(method: :post) do
          attempts += 1
          raise GigaChat::APIError.for(status:)
        end
      end
      assert_equal 1, attempts, "status #{status} must not be retried"
    end
  end

  def test_backoff_is_exponential_jittered_and_capped
    assert_raises(GigaChat::ServerError) do
      policy(max_retries: 6).run(method: :get) { raise GigaChat::APIError.for(status: 502) }
    end

    [0.5, 1.0, 2.0, 4.0, 8.0, 8.0].zip(@slept).each do |ceiling, slept|
      assert_includes((ceiling * 0.75)..ceiling, slept, "delay #{slept} outside #{ceiling * 0.75}..#{ceiling}")
    end
  end

  def test_retry_after_parsing
    retry_after = ->(value) { GigaChat::Internal::RetryPolicy.retry_after({ "retry-after" => value }) }

    assert_in_delta 3.0, retry_after.call("3")
    assert_in_delta 30.0, retry_after.call((Time.now + 30).httpdate), 1.5
    assert_in_delta 60.0, retry_after.call("600"), 0.001, "server delays are capped at 60 s"
    assert_nil retry_after.call("soon")
    assert_nil GigaChat::Internal::RetryPolicy.retry_after({})
  end

  def test_rate_limit_waits_for_retry_after
    attempts = 0

    policy.run(method: :post) do
      attempts += 1
      raise GigaChat::APIError.for(status: 429, headers: { "retry-after" => "2" }) if attempts == 1
    end

    assert_equal [2.0], @slept
    assert_in_delta 2.0, GigaChat::APIError.for(status: 429, headers: { "retry-after" => "2" }).retry_after
  end

  def test_timeouts_retry_only_for_get
    get_attempts = 0
    post_attempts = 0

    assert_raises(GigaChat::APITimeoutError) do
      policy.run(method: :get) { (get_attempts += 1) && wrapped(Faraday::TimeoutError) }
    end
    assert_raises(GigaChat::APITimeoutError) do
      policy.run(method: :post) { (post_attempts += 1) && wrapped(Faraday::TimeoutError) }
    end
    assert_equal 3, get_attempts
    assert_equal 1, post_attempts
  end

  def test_connection_failures_retry_but_ssl_errors_do_not
    failed = 0
    ssl = 0

    assert_raises(GigaChat::APIConnectionError) do
      policy.run(method: :post) { (failed += 1) && wrapped(Faraday::ConnectionFailed) }
    end
    assert_raises(GigaChat::APIConnectionError) do
      policy.run(method: :get) { (ssl += 1) && wrapped(Faraday::SSLError) }
    end
    assert_equal 3, failed
    assert_equal 1, ssl
  end

  def test_non_replayable_and_vetoed_requests_are_not_retried
    attempts = 0
    server_error = -> { (attempts += 1) && raise(GigaChat::APIError.for(status: 503)) }

    assert_raises(GigaChat::ServerError) { policy.run(method: :post, replayable: false) { server_error.call } }
    assert_raises(GigaChat::ServerError) { policy.run(method: :post, retry_if: -> { false }) { server_error.call } }
    assert_equal 2, attempts
  end
end
