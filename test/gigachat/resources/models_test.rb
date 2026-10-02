# frozen_string_literal: true

require "test_helper"

class ModelsTest < GigaChatTestCase
  def setup
    super
    stub_oauth
    @client = build_client
  end

  def test_list
    model = { id: "GigaChat-2", object: "model", owned_by: "salutedevices", type: "chat" }
    stub_request(:get, "#{API}/models").to_return(json_response({ object: "list", data: [model] }))

    assert_equal ["chat"], @client.models.list.map(&:type)
  end

  def test_retrieve
    stub_request(:get, "#{API}/models/GigaChat-2-Max").to_return(json_response({ id: "GigaChat-2-Max", type: "chat" }))

    assert_equal "GigaChat-2-Max", @client.models.retrieve("GigaChat-2-Max").id
  end
end
