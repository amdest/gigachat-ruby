# frozen_string_literal: true

require_relative "live_helper"

class SmokeTest < LiveTestCase
  WEATHER = {
    name: "weather_forecast",
    description: "Returns the weather forecast for a city",
    parameters: { type: "object", properties: { location: { type: "string", description: "City" } },
                  required: ["location"] },
    return_parameters: { type: "object", properties: { temperature: { type: "integer" } } }
  }.freeze

  def test_token
    refute_empty @client.token.access_token
  end

  def test_models_include_a_chat_model
    assert(@client.models.list.any? { it.type == "chat" }, "expected at least one chat model")
  end

  def test_chat_v2_create
    completion = @client.chat.create(messages: [{ role: "user", content: "Ответь одним словом: столица России?" }])

    refute_empty completion.text
    assert_operator completion.usage.total_tokens, :>, 0
  end

  # Spec §13, question 1: the v2 stream payload shape.
  def test_chat_v2_stream_payload_shape
    deltas = []

    final = @client.chat.stream(messages: [{ role: "user", content: "Сосчитай от 1 до 5" }]) do |event|
      deltas << event.text if event.delta?
    end

    refute_empty final.text, "accumulated v2 stream text must not be empty"
    assert_equal deltas.join, final.text
    refute_nil final.finish_reason
  end

  # Spec §13, question 2: is tools_state_id accepted back in requests?
  def test_chat_v2_function_round_trip_with_tools_state_id
    tools = [{ functions: { specifications: [WEATHER] } }]
    messages = [{ role: "user", content: "Какая погода в Туле?" }]

    first = @client.chat.create(messages:, tools:, tool_config: { mode: "forced", function_name: "weather_forecast" })
    call = first.function_call

    refute_nil call, "forced mode must return a function call"
    refute_nil first.message.tools_state_id, "the response must carry tools_state_id"
    messages += [
      first.message,
      { role: "tool", tools_state_id: first.message.tools_state_id,
        content: [{ function_result: { name: call.name, result: JSON.generate({ temperature: 12 }) } }] }
    ]

    refute_empty @client.chat.create(messages:, tools:).text
  end

  def test_chat_v1_create_and_stream
    refute_empty @client.chat.v1.create(messages: [{ role: "user", content: "Привет!" }]).text
    refute_empty(@client.chat.v1.stream(messages: [{ role: "user", content: "Привет!" }]) { nil }.text)
  end

  def test_embeddings
    vectors = @client.embeddings.create(input: %w[Привет Мир]).vectors

    assert_equal 2, vectors.size
    assert(vectors.all? { it.is_a?(Array) && !it.empty? })
  end

  def test_tokens_count
    assert_operator @client.tokens_count(input: ["Я к вам пишу — чего же боле?"]).first.tokens, :>, 0
  end

  # Spec §13, question 3: does files.content work with Accept: */*?
  def test_file_lifecycle
    uploaded = @client.files.upload(StringIO.new("Привет, GigaChat!"), filename: "smoke.txt")

    assert_equal uploaded.id, @client.files.retrieve(uploaded.id).id
    assert_includes @client.files.content(uploaded.id).force_encoding(Encoding::UTF_8), "GigaChat"
  ensure
    assert_predicate @client.files.delete(uploaded.id), :deleted? if uploaded
  end

  def test_functions_validate
    function = WEATHER.merge(few_shot_examples: [{ request: "Погода в Москве", params: { location: "Москва" } }])

    assert_predicate @client.functions.validate(function), :valid?
  end

  def test_balance
    require_scope!("GIGACHAT_API_PERS", "GIGACHAT_API_B2B")

    assert(@client.balance.all? { it.value.is_a?(Integer) })
  end

  def test_ai_check
    require_scope!("GIGACHAT_API_CORP")
    text = "Первый искусственный спутник Земли был запущен Советским Союзом 4 октября 1957 года. " \
           "Этот исторический запуск ознаменовал начало космической эры и стал важным событием в истории."

    assert_includes %w[ai human mixed], @client.ai_check(input: text, model: "GigaCheckClassification").category
  end

  # Spec §13, question 4: the GET /batches shape.
  def test_batches_list
    require_scope!("GIGACHAT_API_CORP")

    assert_kind_of GigaChat::Types::BatchList, @client.batches.list
  end
end
