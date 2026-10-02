# frozen_string_literal: true

require "test_helper"

class TypesBaseTest < GigaChatTestCase
  class Item < GigaChat::Types::Base
    attribute :name
  end

  class Box < GigaChat::Types::Base
    attribute :label
    attribute :item, Item
    attribute :items, Item, array: true
  end

  class Bag < GigaChat::Types::Base
    enumerable :items, Item
  end

  def test_typed_readers_convert_nested_hashes
    box = Box.new({ label: "a", item: { name: "x" }, items: [{ name: "y" }] })

    assert_equal "a", box.label
    assert_instance_of Item, box.item
    assert_equal ["y"], box.items.map(&:name)
  end

  def test_unknown_fields_stay_reachable
    box = Box.new({ "label" => "a", "brand_new" => { deep: 1 } })

    assert_equal({ deep: 1 }, box[:brand_new])
    assert_equal 1, box.dig(:brand_new, :deep)
    assert_equal "a", box["label"]
  end

  def test_to_json_round_trips_raw_data
    box = Box.new({ label: "Привет", item: { name: "x" } })

    assert_equal({ "label" => "Привет", "item" => { "name" => "x" } }, JSON.parse(JSON.generate({ box: }))["box"])
  end

  def test_pattern_matching
    result = case Box.new({ label: "length" })
             in { label: "length" } then :matched
             else :missed
             end

    assert_equal :matched, result
  end

  def test_equality_compares_class_and_data
    assert_equal Item.new({ name: "x" }), Item.new({ "name" => "x" })
    refute_equal Item.new({ name: "x" }), Box.new({ name: "x" })
  end

  def test_enumerable_keeps_raw_to_h
    bag = Bag.new({ items: [{ name: "a" }, { name: "b" }] })

    assert_equal %w[a b], bag.map(&:name)
    assert_equal({ items: [{ name: "a" }, { name: "b" }] }, bag.to_h, "to_h must return raw data, not Enumerable#to_h")
  end

  def test_request_id_comes_from_x_headers
    assert_equal "req-1", Box.new({}, x_headers: { "x-request-id" => "req-1" }).request_id
  end
end
