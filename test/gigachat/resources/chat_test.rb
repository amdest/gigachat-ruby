# frozen_string_literal: true

require "logger"
require "test_helper"

class ChatTest < GigaChatTestCase
  class ClientGone < IOError
  end

  def setup
    super
    stub_oauth
    @client = build_client(model: "GigaChat-2-Max")
  end

  def user(content) = { role: "user", content: }

  def stub_v2_stream(body = fixture("chat_v2_stream.sse"))
    stub_request(:post, V2_CHAT).to_return(status: 200, body:, headers: SSE_HEADERS)
  end

  def test_create_accepts_stream_false
    stub_request(:post, V2_CHAT).to_return(json_response(fixture("chat_v2_completion.json")))

    refute_empty @client.chat.create(messages: [user("hi")], stream: false).text
  end

  def test_exceptions_from_the_stream_block_surface_unchanged
    stub_v2_stream

    assert_raises(ClientGone) { @client.chat.stream(messages: [user("hi")]) { raise ClientGone, "browser left" } }
    assert_requested(:post, V2_CHAT, times: 1)
  end

  def test_completed_stream_is_logged
    stub_v2_stream
    log = StringIO.new

    build_client(model: "m", logger: Logger.new(log)).chat.stream(messages: [user("hi")]) { nil }

    assert_match(/POST #{Regexp.escape(V2_CHAT)} 200 \d+ms req=req-s/, log.string)
  end

  def test_stream_replays_once_after_an_expired_token
    stub_request(:post, AUTH).to_return(json_response({ access_token: "old", expires_at: future_ms }),
                                        json_response({ access_token: "new", expires_at: future_ms }))
    stub_request(:post, V2_CHAT).with(headers: { "Authorization" => "Bearer old" })
                                .to_return(json_response({ message: "Token has expired" }, status: 401))
    stub_request(:post, V2_CHAT).with(headers: { "Authorization" => "Bearer new" })
                                .to_return(status: 200, body: fixture("chat_v2_stream.sse"), headers: SSE_HEADERS)

    assert_equal "GigaChat — это сервис.", @client.chat.stream(messages: [user("hi")]).response.text
    assert_requested(:post, AUTH, times: 2)
  end

  def test_stream_is_not_retried_after_the_first_event
    delta = { messages: [{ role: "assistant", content: [{ text: "Hi" }] }] }
    stub_v2_stream("event: response.message.delta\ndata: #{JSON.generate(delta)}\n\n" \
                   "event: error\ndata: {\"status\":503,\"message\":\"overloaded\"}\n\n")
    seen = []

    assert_raises(GigaChat::ServerError) { @client.chat.stream(messages: [user("hi")]) { seen << it.text } }
    assert_equal ["Hi"], seen
    assert_requested(:post, V2_CHAT, times: 1)
  end

  def test_create_posts_v2_body_and_normalizes_string_content
    stub_request(:post, V2_CHAT).to_return(json_response(fixture("chat_v2_completion.json")))

    completion = @client.chat.create(messages: [user("Привет")], model_options: { temperature: 0.2 })

    assert_equal "GigaChat — это сервис, который умеет вести диалог.", completion.text
    expected = { model: "GigaChat-2-Max", messages: [{ role: "user", content: [{ text: "Привет" }] }],
                 model_options: { temperature: 0.2 } }

    assert_requested(:post, V2_CHAT, body: expected)
  end

  def test_create_rejects_the_stream_flag
    assert_raises(ArgumentError) { @client.chat.create(messages: [user("hi")], stream: true) }
  end

  def test_create_requires_a_model_before_sending
    assert_raises(GigaChat::ModelNotSpecifiedError) { build_client.chat.create(messages: [user("hi")]) }
    assert_not_requested(:post, V2_CHAT)
  end

  def test_response_objects_round_trip_into_requests
    stub_request(:post, V2_CHAT).to_return(json_response(fixture("chat_v2_completion.json")))
    first = @client.chat.create(messages: [user("Привет")])

    @client.chat.create(messages: [user("Привет"), first.message, { "role" => "user", "content" => "Ещё" }])

    assert_requested(:post, V2_CHAT) do |req|
      sent = JSON.parse(req.body)["messages"]
      sent.size == 3 && sent[1] == JSON.parse(JSON.generate(first.message.to_h)) &&
        sent[2] == { "role" => "user", "content" => [{ "text" => "Ещё" }] }
    end
  end

  def test_stream_block_returns_the_accumulated_response
    stub_request(:post, V2_CHAT).to_return(status: 200, body: fixture("chat_v2_stream.sse"), headers: SSE_HEADERS)
    deltas = []

    response = @client.chat.stream(messages: [user("Привет")]) { |event| deltas << event.text if event.delta? }

    assert_equal ["GigaChat — это ", "сервис."], deltas
    assert_equal "GigaChat — это сервис.", response.text
    assert_equal "req-s", response.request_id
    assert_requested(:post, V2_CHAT) do |req|
      JSON.parse(req.body)["stream"] == true && req.headers["Accept"] == "text/event-stream"
    end
  end

  def test_stream_without_a_block_is_lazy
    stub = stub_request(:post, V2_CHAT)
           .to_return(status: 200, body: fixture("chat_v2_stream.sse"), headers: SSE_HEADERS)

    stream = @client.chat.stream(messages: [user("hi")])

    assert_not_requested(stub)
    assert_equal 3, stream.count
    assert_requested(stub, times: 1)
  end

  def test_stream_http_error_raises_with_the_body
    stub_request(:post, V2_CHAT)
      .to_return(json_response({ status: 422, message: "Invalid params: messages" }, status: 422))

    error = assert_raises(GigaChat::UnprocessableEntityError) { @client.chat.stream(messages: [user("hi")]) { nil } }
    assert_match(/Invalid params: messages/, error.message)
  end

  def test_stream_rejects_a_non_sse_success
    stub_request(:post, V2_CHAT).to_return(json_response({ messages: [] }))

    error = assert_raises(GigaChat::APIError) { @client.chat.stream(messages: [user("hi")]).each { nil } }
    assert_match(%r{text/event-stream}, error.message)
  end

  def test_stream_retries_before_the_first_event
    stub_request(:post, V2_CHAT).to_return(json_response({ message: "busy" }, status: 503))
                                .then.to_return(status: 200, body: fixture("chat_v2_stream.sse"), headers: SSE_HEADERS)

    assert_equal "GigaChat — это сервис.", @client.chat.stream(messages: [user("hi")]).response.text
    assert_requested(:post, V2_CHAT, times: 2)
  end

  def test_v1_create_keeps_string_content
    stub_request(:post, "#{API}/chat/completions").to_return(json_response(fixture("chat_v1_completion.json")))

    completion = @client.chat.v1.create(messages: [user("Hi")])

    assert_match(/\AGigaChat is a service/, completion.text)
    assert_requested(:post, "#{API}/chat/completions", body: { model: "GigaChat-2-Max", messages: [user("Hi")] })
  end

  def test_v1_stream
    stub_request(:post, "#{API}/chat/completions").to_return(status: 200, body: fixture("chat_v1_stream.sse"),
                                                             headers: SSE_HEADERS)

    assert_equal "GigaChat — это сервис.", @client.chat.v1.stream(messages: [user("Hi")]) { nil }.text
  end
end
