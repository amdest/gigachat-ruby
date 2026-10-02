# frozen_string_literal: true

require "test_helper"

class GigaChatTest < GigaChatTestCase
  def test_version_is_semantic
    assert_match(/\A\d+\.\d+\.\d+\z/, GigaChat::VERSION, "VERSION must be MAJOR.MINOR.PATCH")
  end

  def test_every_file_eager_loads
    GigaChat::LOADER.eager_load(force: true)

    assert_kind_of Module, GigaChat, "eager loading must define every constant without NameError"
  end

  def test_bundler_shim_loads_the_library
    assert load(File.expand_path("../lib/gigachat-ruby.rb", __dir__)), "lib/gigachat-ruby.rb must load cleanly"
  end
end
