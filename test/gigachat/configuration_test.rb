# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < GigaChatTestCase
  def test_defaults
    config = GigaChat::Configuration.resolve({})

    assert_equal "https://api.giga.chat/v1", config.base_url
    assert_equal "https://ngw.devices.sberbank.ru:9443/api/v2/oauth", config.auth_url
    assert_equal "GIGACHAT_API_PERS", config.scope
    assert_equal 2, config.max_retries
    assert_equal 60, config.timeout
    assert config.verify_ssl_certs, "TLS verification must default to on"
    assert config.bundled_ca, "the bundled CA must default to on"
  end

  def test_precedence_is_kwargs_then_global_then_env_then_defaults
    ENV["GIGACHAT_MODEL"] = "env-model"
    ENV["GIGACHAT_SCOPE"] = "GIGACHAT_API_B2B"
    ENV["GIGACHAT_TIMEOUT"] = "15"
    GigaChat.configure do |c|
      c.model = "global-model"
      c.scope = "GIGACHAT_API_CORP"
    end

    config = GigaChat::Configuration.resolve({ model: "kwarg-model" })

    assert_equal "kwarg-model", config.model
    assert_equal "GIGACHAT_API_CORP", config.scope
    assert_in_delta 15.0, config.timeout
  end

  def test_nil_option_does_not_override
    ENV["GIGACHAT_MODEL"] = "env-model"

    assert_equal "env-model", GigaChat::Configuration.resolve({ model: nil }).model
  end

  def test_env_booleans_are_case_and_space_insensitive
    { "False" => false, " NO " => false, "0" => false, "TRUE" => true, "on" => true }.each do |raw, expected|
      ENV["GIGACHAT_VERIFY_SSL_CERTS"] = raw

      assert_equal expected, GigaChat::Configuration.resolve({}).verify_ssl_certs, "#{raw.inspect} => #{expected}"
    end
  end

  def test_invalid_env_value_names_the_variable
    ENV["GIGACHAT_MAX_RETRIES"] = "many"

    error = assert_raises(GigaChat::ConfigurationError) { GigaChat::Configuration.resolve({}) }
    assert_match(/GIGACHAT_MAX_RETRIES/, error.message)
  end

  def test_unknown_option_raises
    error = assert_raises(GigaChat::ConfigurationError) { GigaChat::Configuration.resolve({ modle: "x" }) }

    assert_match(/modle/, error.message)
  end

  def test_inspect_masks_secrets
    config = GigaChat::Configuration.resolve({ credentials: "cred-SECRET", password: "pass-SECRET",
                                               access_token: "token-SECRET", key_file_password: "key-SECRET" })

    refute_match(/SECRET/, config.inspect)
    assert_match(/credentials=\[FILTERED\]/, config.inspect)
  end

  def test_resolve_model
    config = GigaChat::Configuration.resolve({})

    assert_equal "GigaChat-2", config.resolve_model("GigaChat-2")
    assert_raises(GigaChat::ModelNotSpecifiedError) { config.resolve_model(nil) }
  end
end
