# frozen_string_literal: true

require "test_helper"

class BatchesTest < GigaChatTestCase
  def setup
    super
    stub_oauth
    @client = build_client
  end

  def test_create_encodes_requests_as_jsonl
    stub_request(:post, "#{API}/batches?method=chat_completions").to_return(
      json_response({ id: "b-1", method: "chat_completions", request_counts: { total: 2 }, status: "created" })
    )
    requests = [
      { id: "1", request: { model: "GigaChat-2", messages: [{ role: "user", content: "Привет" }] } },
      { id: "2", request: { model: "GigaChat-2", messages: [{ role: "user", content: "Пока" }] } }
    ]

    batch = @client.batches.create(requests, method: :chat_completions)

    assert_equal "chat_completions", batch.batch_method
    assert_requested(:post, "#{API}/batches?method=chat_completions") do |req|
      lines = req.body.dup.force_encoding(Encoding::UTF_8).lines
      req.headers["Content-Type"] == "application/octet-stream" && lines.size == 2 &&
        JSON.parse(lines.last)["request"]["messages"].first["content"] == "Пока"
    end
  end

  def test_create_rejects_an_unknown_method
    assert_raises(ArgumentError) { @client.batches.create([], method: :images) }
  end

  def test_list_and_retrieve
    stub_request(:get, "#{API}/batches").to_return(json_response({ batches: [{ id: "b-1", status: "in_progress" }] }))
    stub_request(:get, "#{API}/batches?batch_id=b-1").to_return(
      json_response({ batches: [{ id: "b-1", status: "completed", output_file_id: "out-1" }] })
    )

    assert_equal ["b-1"], @client.batches.list.map(&:id)
    assert_predicate @client.batches.retrieve("b-1"), :completed?
  end

  def test_list_accepts_a_bare_array
    stub_request(:get, "#{API}/batches").to_return(json_response([{ id: "b-9" }]))

    assert_equal ["b-9"], @client.batches.list.map(&:id)
  end

  def test_retrieve_unknown_raises_not_found
    stub_request(:get, "#{API}/batches?batch_id=nope").to_return(json_response({ batches: [] }))

    assert_raises(GigaChat::NotFoundError) { @client.batches.retrieve("nope") }
  end

  def test_results_download_and_parse_jsonl
    stub_request(:get, "#{API}/files/out-1/content").to_return(
      status: 200, body: "{\"id\":\"1\",\"result\":{\"x\":1}}\n\n{\"id\":\"2\",\"result\":{}}\n"
    )
    batch = GigaChat::Types::Batch.new({ id: "b-1", status: "completed", output_file_id: "out-1" })

    assert_equal(%w[1 2], @client.batches.results(batch).map { it[:id] })
  end

  def test_results_without_an_output_file_raise
    batch = GigaChat::Types::Batch.new({ id: "b-1", status: "in_progress" })

    assert_raises(GigaChat::Error) { @client.batches.results(batch) }
  end
end
