# frozen_string_literal: true

module RubyLLM
  module AgUI
    # The policy that decides what a tool result or activity payload may put on
    # the wire.
    #
    # A tool result is arbitrary host data on its way to a browser. It may hold
    # an API key, a customer record or an internal path, and the gem has no way
    # to know which part is a secret. So the default policy publishes the shape
    # and withholds the content, and a host that has decided its payloads are
    # safe says so explicitly:
    #
    #   RubyLLM::AgUI.configure do |config|
    #     config.redact = RubyLLM::AgUI::Redaction.method(:none)   # publish raw
    #     config.redact = ->(kind, payload) { MyPolicy.call(kind, payload) }
    #   end
    #
    # A pattern-matching scrubber is deliberately not the default: it would
    # create confidence in something that cannot be correct, because the gem
    # cannot know what the host considers personal.
    module Redaction
      # What a redacted value becomes.
      PLACEHOLDER = '[redacted]'

      # The kinds a policy is asked about.
      TOOL_RESULT = :tool_result

      module_function

      # The default policy: keep the shape, withhold the content.
      #
      # A Hash keeps its keys, an Array keeps its length, and a scalar becomes
      # the placeholder, so a payload still validates against the schema it
      # travels in while carrying none of its values.
      def default(_kind, payload)
        case payload
        when nil, '' then payload
        when Hash then payload.to_h { |key, _value| [key, PLACEHOLDER] }
        when Array then payload.map { PLACEHOLDER }
        else PLACEHOLDER
        end
      end

      # The opt-out: publish the payload unchanged. Use it only when the host
      # has established that the payload is safe to show.
      def none(_kind, payload)
        payload
      end

      # Calls +callable+ with the arguments its arity takes, so a host can write
      # either `->(kind, payload) { ... }` or the terse `->(payload) { ... }`.
      def apply(callable, kind, payload)
        callable.arity == 1 ? callable.call(payload) : callable.call(kind, payload)
      end
    end
  end
end
