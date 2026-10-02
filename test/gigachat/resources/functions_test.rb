# frozen_string_literal: true

require "test_helper"

class FunctionsTest < GigaChatTestCase
  FUNCTION = { name: "send_sms", parameters: { type: "object", properties: {} } }.freeze

  def setup
    super
    stub_oauth
    stub_request(:post, "#{API}/functions/validate").with(body: FUNCTION).to_return(
      json_response({ status: 200, message: "Function is valid", json_ai_rules_version: "1.0.5",
                      warnings: [{ description: "few_shot_examples are missing", schema_location: "(root)" }] })
    )
    @client = build_client
  end

  def test_validate_with_keywords
    result = @client.functions.validate(**FUNCTION)

    assert_predicate result, :valid?
    assert_equal ["few_shot_examples are missing"], result.warnings.map(&:description)
  end

  def test_validate_with_a_hash
    assert_predicate @client.functions.validate(FUNCTION), :valid?
  end
end
