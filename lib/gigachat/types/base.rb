# frozen_string_literal: true

module GigaChat
  module Types
    # Lenient response object: typed readers for documented fields, raw access for everything else.
    # The API adds fields without notice, so unknown keys are kept and never raise.
    class Base
      class << self
        def attributes
          @attributes ||= superclass.respond_to?(:attributes) ? superclass.attributes.dup : {}
        end

        def attribute(name, type = nil, array: false)
          attributes[name] = [type, array]
          define_method(name) { read_attribute(name) }
        end

        # Declares the list field the object enumerates over.
        def enumerable(name, type)
          attribute(name, type, array: true)
          include Enumerable

          define_method(:each) { |&block| (public_send(name) || []).each(&block) }
          define_method(:to_h) { @data } # Enumerable#to_h would otherwise shadow Base#to_h
        end

        def coerce(value)
          return new(value.to_h) if value.is_a?(Base) && !value.is_a?(self)
          return new(value) if value.is_a?(Hash)

          value
        end
      end

      attr_reader :x_headers

      def initialize(data = {}, x_headers: nil)
        @data = data.to_h.transform_keys(&:to_sym).freeze
        @x_headers = x_headers || {}
        @cache = {}
      end

      def [](key) = @data[key.to_sym]

      def dig(*keys) = @data.dig(*keys)

      def to_h = @data

      def to_json(*) = @data.to_json(*)

      def deconstruct_keys(keys) = keys ? @data.slice(*keys) : @data

      def request_id = @x_headers["x-request-id"]

      def ==(other) = other.class == self.class && other.to_h == @data

      alias eql? ==

      def hash = [self.class, @data].hash

      def inspect = "#<#{self.class.name} #{@data.inspect}>"

      alias to_s inspect

      private

      def read_attribute(name)
        return @cache[name] if @cache.key?(name)

        type, array = self.class.attributes.fetch(name)
        raw = @data[name]
        @cache[name] =
          if type.nil? || raw.nil? then raw
          elsif array then (raw.is_a?(Array) ? raw : [raw]).map { type.coerce(it) }
          else type.coerce(raw)
          end
      end
    end
  end
end
