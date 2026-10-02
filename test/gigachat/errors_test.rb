# frozen_string_literal: true

require "test_helper"

class ErrorsTest < GigaChatTestCase
  def test_for_maps_documented_statuses
    expected = {
      400 => GigaChat::BadRequestError, 401 => GigaChat::AuthenticationError,
      402 => GigaChat::PaymentRequiredError,
      403 => GigaChat::PermissionDeniedError, 404 => GigaChat::NotFoundError,
      413 => GigaChat::RequestEntityTooLargeError, 422 => GigaChat::UnprocessableEntityError,
      429 => GigaChat::RateLimitError, 500 => GigaChat::ServerError, 503 => GigaChat::ServerError,
      418 => GigaChat::APIError
    }

    expected.each do |status, error_class|
      assert_instance_of error_class, GigaChat::APIError.for(status:), "status #{status} should map to #{error_class}"
    end
  end

  def test_message_combines_status_body_message_and_request_id
    error = GigaChat::APIError.for(status: 422, body: { status: 422, message: "Invalid params: x" },
                                   headers: { "x-request-id" => "req-9" })

    assert_equal "422 Invalid params: x (request_id: req-9)", error.message
    assert_equal "req-9", error.request_id
  end

  def test_message_falls_back_to_squashed_text_body
    error = GigaChat::APIError.for(status: 502, body: "<html>\n  Bad Gateway\n</html>")

    assert_equal "502 <html> Bad Gateway </html>", error.message
  end

  def test_message_falls_back_to_compact_json_without_a_message_field
    error = GigaChat::APIError.for(status: 400, body: { status: 400, error: "bad things" })

    assert_equal '400 {"status":400,"error":"bad things"}', error.message
  end

  def test_hierarchy
    assert_operator GigaChat::APITimeoutError, :<, GigaChat::APIConnectionError
    assert_operator GigaChat::APIConnectionError, :<, GigaChat::Error
    assert_operator GigaChat::RateLimitError, :<, GigaChat::APIError
    assert_operator GigaChat::ModelNotSpecifiedError, :<, GigaChat::Error
  end
end
