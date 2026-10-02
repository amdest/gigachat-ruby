# frozen_string_literal: true

require "test_helper"

class ChatTest < GigaChatTestCase
  def setup
    super
    stub_oauth
    @client = build_client(model: "GigaChat-2-Max")
  end

  def user(content) = { role: "user", content: }

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
