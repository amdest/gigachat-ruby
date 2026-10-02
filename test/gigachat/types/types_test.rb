# frozen_string_literal: true

require "test_helper"

class TypesTest < GigaChatTestCase
  def test_chat_completion_helpers
    completion = GigaChat::Types::ChatCompletion.new(json_fixture("chat_v2_completion.json"))

    assert_equal "GigaChat — это сервис, который умеет вести диалог.", completion.text
    assert_equal "assistant", completion.message.role
    assert_equal 85, completion.usage.total_tokens
    assert_equal 1_760_434_636, completion.created_at
    assert_nil completion.function_call
  end

  def test_chat_completion_function_call_and_files
    completion = GigaChat::Types::ChatCompletion.new(json_fixture("chat_v2_function_call.json"))

    assert_equal "weather_forecast", completion.function_call.name
    assert_equal({ location: "Болхов", num_days: 7 }, completion.function_call.arguments)
    assert_equal ["image"], completion.files.map(&:target)
    assert_equal "", completion.text
  end

  def test_created_at_falls_back_to_created
    assert_equal 5, GigaChat::Types::ChatCompletion.new({ created: 5 }).created_at
  end

  def test_function_call_arguments_are_always_a_hash
    arguments = ->(raw) { GigaChat::Types::FunctionCall.new({ name: "f", arguments: raw }).arguments }

    assert_equal({ a: 1 }, arguments.call('{"a":1}'))
    assert_equal({ a: 1 }, arguments.call({ a: 1 }))
    assert_equal({}, arguments.call("not json"))
    assert_equal({}, arguments.call(nil))
  end

  def test_chat_event_predicates
    event = GigaChat::Types::ChatEvent.new({}, type: "response.message.done")

    assert_predicate event, :done?
    refute_predicate event, :delta?
    assert_equal "", event.text
  end

  def test_v1_completion
    completion = GigaChat::Types::V1::ChatCompletion.new(json_fixture("chat_v1_completion.json"))

    assert_match(/\AGigaChat is a service/, completion.text)
    assert_equal 4, completion.usage.precached_prompt_tokens
    assert_equal "stop", completion.choices.first.finish_reason
  end

  def test_v1_function_call_arguments_object
    message = GigaChat::Types::V1::ChatCompletion.new(json_fixture("chat_v1_function_call.json")).choices.first.message

    assert_equal({ location: "Манжерок", num_days: 10 }, message.function_call.arguments)
    assert_equal "0199e210-2f13-744c-8fe5-c9a19fe27db7", message.functions_state_id
  end

  def test_v1_chunk_text_joins_deltas
    chunk = GigaChat::Types::V1::ChatCompletionChunk.new(
      { choices: [{ delta: { content: "При" }, index: 0 }, { delta: { content: "вет" }, index: 1 }] }
    )

    assert_equal "Привет", chunk.text
  end

  def test_lists_and_predicates
    assert_equal [[0.1], [0.2]],
                 GigaChat::Types::Embeddings.new({ data: [{ embedding: [0.1] }, { embedding: [0.2] }] }).vectors
    assert_equal %w[GigaChat-2 Embeddings],
                 GigaChat::Types::ModelList.new({ data: [{ id: "GigaChat-2" }, { id: "Embeddings" }] }).map(&:id)
    assert_predicate GigaChat::Types::AiCheckResult.new({ category: "ai" }), :ai?
    assert_predicate GigaChat::Types::FileDeleted.new({ deleted: true }), :deleted?
    assert_equal [100_500],
                 GigaChat::Types::Balance.new({ balance: [{ usage: "GigaChat", value: 100_500 }] }).map(&:value)
    assert_equal [7], GigaChat::Types::TokensCountList.new({ data: [{ tokens: 7 }] }).map(&:tokens)
  end

  def test_function_validation
    result = GigaChat::Types::FunctionValidation.new(
      { message: "Incorrect function syntax", errors: [{ description: "name is required", schema_location: "(root)" }] }
    )

    refute_predicate result, :valid?
    assert_equal "(root)", result.errors.first.schema_location
  end

  def test_batch_and_batch_list
    batch = GigaChat::Types::Batch.new(
      { id: "b", method: "embedder", status: "completed", request_counts: { total: 3, completed: 2, failed: 1 } }
    )

    assert_equal "embedder", batch.batch_method
    assert_predicate batch, :completed?
    assert_equal 1, batch.request_counts.failed
    assert_equal ["b-1"], GigaChat::Types::BatchList.new({ batches: [{ id: "b-1" }] }).map(&:id)
    assert_equal ["b-2"], GigaChat::Types::BatchList.new({ data: [{ id: "b-2" }] }).map(&:id)
  end
end
