# frozen_string_literal: true

module RubyLLM
  module AgUI
    # Shared shape checks for untrusted JSON.
    #
    # Every method raises an InputError subclass whose message names the
    # offending member but never quotes the value, so a host can return it to
    # the client without echoing request bytes back.
    #
    # Included by RubyLLM::AgUI::Input::Parser and RubyLLM::AgUI::MessageParser.
    module Validation
      # The longest accepted id (threadId, runId, message id, interrupt id).
      MAX_ID_LENGTH = 255

      # The longest accepted free-text string.
      MAX_CONTENT_LENGTH = 1_000_000

      private

      def identifier!(value, name, required: true)
        return nil if value.nil? && !required

        raise InvalidInputError, "#{name} is required." if value.nil?
        raise InvalidInputError, "#{name} must be a string." unless value.is_a?(String)
        raise InvalidInputError, "#{name} must not be empty." if value.empty?
        raise InvalidInputError, "#{name} is too long." if value.length > MAX_ID_LENGTH

        value
      end

      def string!(value, name, max: MAX_CONTENT_LENGTH)
        raise InvalidInputError, "#{name} is required." if value.nil?
        raise InvalidInputError, "#{name} must be a string." unless value.is_a?(String)
        raise InvalidInputError, "#{name} is too long." if value.length > max

        value
      end

      def optional_string(value, name)
        return nil if value.nil?

        string!(value, name)
      end

      def array!(value, name, required: false, max: nil)
        return [] if value.nil? && !required

        raise InvalidInputError, "#{name} is required." if value.nil?
        raise InvalidInputError, "#{name} must be an array." unless value.is_a?(Array)
        raise InputTooLargeError, "#{name} exceeds the #{max} entry limit." if max && value.size > max

        value
      end

      def object!(value, name)
        raise InvalidInputError, "#{name} must be an object." unless value.is_a?(Hash)

        value
      end
    end
  end
end
