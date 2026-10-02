# frozen_string_literal: true

require "test_helper"

class SSEDecoderTest < GigaChatTestCase
  def decode(*chunks)
    decoder = GigaChat::Internal::SSEDecoder.new
    events = []
    chunks.each { |chunk| decoder.feed(chunk) { events << it } }
    decoder.finish { events << it }
    events
  end

  def test_named_events
    events = decode("event: response.message.delta\ndata: {\"a\":1}\n\n")

    assert_equal([["response.message.delta", "{\"a\":1}"]], events.map { [it.event, it.data] })
  end

  def test_lines_split_across_chunks
    assert_equal %w[hello world], decode("da", "ta: hel", "lo\n", "\ndata: world\n\n").map(&:data)
  end

  def test_crlf_split_between_chunks_is_one_line_break
    assert_equal ["a\nb"], decode("data: a\r", "\ndata: b\r\n\r\n").map(&:data)
  end

  def test_cyrillic_split_inside_a_character
    bytes = "data: Привет\n\n".b
    cut = bytes.index("\xD0\x9F".b) + 1 # in the middle of "П"

    event = decode(bytes.byteslice(0, cut), bytes.byteslice(cut..)).first

    assert_equal "Привет", event.data
    assert_equal Encoding::UTF_8, event.data.encoding
  end

  def test_bom_comments_multiline_data_and_id
    event = decode("\xEF\xBB\xBF: keep-alive\ndata: line1\ndata: line2\nid: 7\n\n".b).first

    assert_equal "line1\nline2", event.data
    assert_equal "7", event.id
  end

  def test_trailing_event_without_blank_line_is_flushed
    assert_equal ["[DONE]"], decode("data: [DONE]").map(&:data)
  end

  def test_value_without_space_and_bare_cr_line_endings
    assert_equal ["x"], decode("data:x\r\r").map(&:data)
  end

  def test_event_without_data_is_not_dispatched
    assert_empty decode("event: ping\n\n")
  end
end
