# frozen_string_literal: true

module RubyLLM
  module AgUI
    # Isolated JSON-shaped values for request and storage boundaries.
    module Immutable # :nodoc:
      module_function

      def copy(value)
        case value
        when Hash
          value.to_h { |key, item| [copy(key), copy(item)] }.freeze
        when Array
          value.map { |item| copy(item) }.freeze
        when String, Time
          value.dup.freeze
        when ::AgUiProtocol::Core::Types::Model
          copy_model(value)
        else
          value
        end
      end

      def copy_model(value)
        value.dup.tap do |model|
          model.instance_variables.each do |name|
            model.instance_variable_set(name, copy(model.instance_variable_get(name)))
          end
        end.freeze
      end
      private_class_method :copy_model
    end
  end
end
