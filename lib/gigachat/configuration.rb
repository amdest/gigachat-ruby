# frozen_string_literal: true

module GigaChat
  # Client settings. `GigaChat.config` holds global overrides; `Configuration.resolve` builds a client's
  # effective settings with precedence: explicit options > global config > GIGACHAT_* env > defaults.
  class Configuration
    DEFAULTS = {
      credentials: nil, scope: "GIGACHAT_API_PERS", access_token: nil, user: nil, password: nil,
      base_url: "https://api.giga.chat/v1", auth_url: "https://ngw.devices.sberbank.ru:9443/api/v2/oauth",
      model: nil, timeout: 60, open_timeout: 10, max_retries: 2,
      verify_ssl_certs: true, bundled_ca: true, ca_bundle_file: nil,
      cert_file: nil, key_file: nil, key_file_password: nil,
      client_id: nil, session_id: nil, logger: nil
    }.freeze

    # Same names as the Python SDK, so one .env serves both.
    ENV_VARS = {
      credentials: "GIGACHAT_CREDENTIALS", scope: "GIGACHAT_SCOPE", access_token: "GIGACHAT_ACCESS_TOKEN",
      user: "GIGACHAT_USER", password: "GIGACHAT_PASSWORD", base_url: "GIGACHAT_BASE_URL",
      auth_url: "GIGACHAT_AUTH_URL", model: "GIGACHAT_MODEL", timeout: "GIGACHAT_TIMEOUT",
      max_retries: "GIGACHAT_MAX_RETRIES", verify_ssl_certs: "GIGACHAT_VERIFY_SSL_CERTS",
      ca_bundle_file: "GIGACHAT_CA_BUNDLE_FILE", cert_file: "GIGACHAT_CERT_FILE",
      key_file: "GIGACHAT_KEY_FILE", key_file_password: "GIGACHAT_KEY_FILE_PASSWORD"
    }.freeze

    SECRETS = %i[credentials access_token password key_file_password].freeze
    BOOLEANS = {
      "true" => true, "1" => true, "yes" => true, "on" => true,
      "false" => false, "0" => false, "no" => false, "off" => false
    }.freeze

    DEFAULTS.each_key do |key|
      define_method(key) { @values[key] }
      define_method(:"#{key}=") { |value| @values[key] = value }
    end

    def self.resolve(options = {}, global: GigaChat.config, env: ENV)
      explicit = options.compact
      config = new(explicit)
      DEFAULTS.each do |key, default|
        next if explicit.key?(key)

        value = global.set?(key) ? global.public_send(key) : from_env(key, env, default)
        config.public_send(:"#{key}=", value)
      end
      config
    end

    def self.from_env(key, env, default)
      raw = ENV_VARS[key] && env[ENV_VARS[key]]
      return default if raw.nil? || raw.strip.empty?

      cast(key, raw)
    end

    def self.cast(key, raw)
      case key
      when :verify_ssl_certs then BOOLEANS.fetch(raw.strip.downcase) { invalid!(key, raw) }
      when :max_retries then Integer(raw.strip, 10) # base 10: "010" is ten, not octal eight
      when :timeout then Float(raw.strip)
      else raw
      end
    rescue ArgumentError
      invalid!(key, raw)
    end

    def self.invalid!(key, raw)
      raise ConfigurationError, "Invalid value for #{ENV_VARS[key]}: #{raw.inspect}"
    end

    private_class_method :from_env, :cast, :invalid!

    def initialize(values = {})
      unknown = values.keys - DEFAULTS.keys
      raise ConfigurationError, "Unknown option(s): #{unknown.join(", ")}" if unknown.any?

      @values = values.dup
    end

    # nil means "not set", as for keyword options: `c.base_url = ENV["PROXY_URL"]` must not wipe the default.
    def set?(key) = !@values[key].nil?

    def to_h = @values.dup

    def resolve_model(model)
      model || self.model || raise(ModelNotSpecifiedError, "Pass model: or set a default model (GIGACHAT_MODEL)")
    end

    def inspect
      pairs = @values.map { |key, value| "#{key}=#{SECRETS.include?(key) && value ? "[FILTERED]" : value.inspect}" }
      "#<#{self.class.name} #{pairs.join(", ")}>"
    end
  end
end
