# frozen_string_literal: true

require "test_helper"

class StreamTest < GigaChatTestCase
  def stream_from(protocol, *chunks)
    GigaChat::Stream.new(protocol:) do |&on_chunk|
      chunks.each { on_chunk.call(it, { "x-request-id" => "req-s" }) }
    end
  end

  def test_v2_events_and_accumulated_response
    stream = stream_from(:v2, fixture("chat_v2_stream.sse"))

    types = stream.map(&:type)
    response = stream.response

    assert_equal %w[response.message.delta response.message.delta response.message.done], types
    assert_equal "GigaChat — это сервис.", response.text
    assert_equal "ts-1", response.message.tools_state_id
    assert_equal "stop", response.finish_reason
    assert_equal 87, response.usage.total_tokens
    assert_equal "req-s", response.request_id
  end

  def test_v1_stops_at_done_and_accumulates
    stream = stream_from(:v1, fixture("chat_v1_stream.sse"), "data: {\"never\":true}\n\n")

    assert_equal ["GigaChat — это ", "сервис.", ""], stream.map(&:text)
    assert_equal "GigaChat — это сервис.", stream.response.text
    assert_equal 87, stream.response.usage.total_tokens
    assert_equal "stop", stream.response.choices.first.finish_reason
  end

  def test_v2_stops_after_the_done_event
    late = "event: response.message.delta\ndata: {\"messages\":[]}\n\n"

    assert_equal 3, stream_from(:v2, fixture("chat_v2_stream.sse"), late).count
  end

  def test_text_enumerator_skips_empty_deltas
    assert_equal ["GigaChat — это ", "сервис."], stream_from(:v1, fixture("chat_v1_stream.sse")).text.to_a
  end

  def test_error_event_raises_a_typed_error
    stream = stream_from(:v2, "event: error\ndata: {\"status\":429,\"message\":\"Too many requests\"}\n\n")

    error = assert_raises(GigaChat::RateLimitError) { stream.each { nil } }
    assert_match(/Too many requests/, error.message)
  end

  def test_stream_is_single_use
    stream = stream_from(:v1, fixture("chat_v1_stream.sse"))
    stream.each { nil }

    assert_raises(GigaChat::Error) { stream.each { nil } }
  end

  def test_break_keeps_the_partial_response
    stream = stream_from(:v1, fixture("chat_v1_stream.sse"))

    stream.each { |event| break if event }

    assert_equal "GigaChat — это ", stream.response.text
  end

  def test_v2_accumulator_keeps_function_calls_and_skips_tool_progress
    sse = <<~SSE
      event: response.tool.in_progress
      data: {"messages":[{"role":"assistant","content":[{"tool_execution":{"name":"image_generate","seconds_left":5}}]}]}

      event: response.message.delta
      data: {"messages":[{"role":"assistant","content":[{"function_call":{"name":"weather","arguments":{"city":"Тула"}}}]}]}

      event: response.message.done
      data: {"finish_reason":"function_call"}

    SSE

    response = stream_from(:v2, sse).response

    assert_equal({ city: "Тула" }, response.function_call.arguments)
    assert_equal "function_call", response.finish_reason
    assert_nil response.message.content.find(&:tool_execution), "tool progress must not be accumulated"
  end

  def test_v2_accumulator_keeps_the_live_tool_state_id_field
    delta = { messages: [{ role: "assistant", tool_state_id: "ts-live", content: [{ text: "Hi" }] }] }

    response = stream_from(:v2, "event: response.message.delta\ndata: #{JSON.generate(delta)}\n\n").response

    assert_equal "ts-live", response.message.tools_state_id
  end

  def test_v1_function_in_progress_deltas_are_not_accumulated
    progress = { choices: [{ delta: { role: "function_in_progress", content: "5 seconds left" }, index: 0 }] }
    answer = { choices: [{ delta: { role: "assistant", content: "Готово" }, index: 0 }] }
    sse = "data: #{JSON.generate(progress)}\n\ndata: #{JSON.generate(answer)}\n\n"

    assert_equal "Готово", stream_from(:v1, sse).response.text
  end
end
