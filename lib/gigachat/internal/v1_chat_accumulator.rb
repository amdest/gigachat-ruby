# frozen_string_literal: true

module GigaChat
  module Internal
    # Folds v1 stream chunks into one V1::ChatCompletion, per choice index.
    class V1ChatAccumulator
      META = %i[created model object usage].freeze

      def initialize
        @meta = {}
        @choices = {}
      end

      def <<(chunk)
        @meta.merge!(chunk.to_h.slice(*META).compact)
        (chunk.choices || []).each { merge_choice(it) }
        self
      end

      def result(x_headers: {})
        choices = @choices.sort.map { |index, choice| choice.merge(index:) }
        Types::V1::ChatCompletion.new({ **@meta, choices: }, x_headers:)
      end

      private

      def merge_choice(choice)
        entry = @choices[choice.index || 0] ||= { message: { role: "assistant", content: +"" } }
        entry[:finish_reason] = choice.finish_reason if choice.finish_reason
        delta = choice.delta
        return if delta.nil? || delta.role == "function_in_progress" # built-in function progress, not content

        message = entry[:message]
        message[:content] << delta.content.to_s
        message[:role] = delta.role if delta.role
        message[:function_call] = delta[:function_call] if delta[:function_call]
        message[:functions_state_id] = delta.functions_state_id if delta.functions_state_id
      end
    end
  end
end
