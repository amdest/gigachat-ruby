# frozen_string_literal: true

require "test_helper"

class EmbeddingsTest < GigaChatTestCase
  def test_create_defaults_to_the_embeddings_model
    stub_oauth
    stub_request(:post, "#{API}/embeddings").with(body: { model: "Embeddings", input: %w[a b] }).to_return(
      json_response({ object: "list", model: "Embeddings",
                      data: [{ object: "embedding", embedding: [0.1, 0.2], index: 0 },
                             { object: "embedding", embedding: [0.3], index: 1 }] })
    )

    result = build_client(model: "GigaChat-2").embeddings.create(input: %w[a b])

    assert_equal [[0.1, 0.2], [0.3]], result.vectors
  end
end
