# frozen_string_literal: true

module RubyLLM
  module AgUI
    # Deterministic serialization and hashing.
    #
    # Run identity depends on comparing an input with the one a retry sends.
    # JSON object member order is not significant, so a naive hash of the raw
    # bytes treats the same request as two. Canonical.dump sorts object keys
    # recursively (like RubyLLM's ToolCall#arguments, so a call reloaded from a
    # database hashes the same), producing a stable string to digest.
    module Canonical
      module_function

      # A deterministic JSON string: object keys sorted by their byte length
      # then value, arrays kept in order.
      def dump(value)
        JSON.generate(sort(value))
      end

      # The SHA-256 hex digest of the canonical form.
      def digest(value)
        Digest::SHA256.hexdigest(dump(value))
      end

      # A recursively key-sorted copy of +value+.
      def sort(value)
        case value
        when Hash
          value.sort_by { |key, _| [key.to_s.bytesize, key.to_s] }
               .to_h { |key, nested| [key.to_s, sort(nested)] }
        when Array
          value.map { |item| sort(item) }
        else
          value
        end
      end
    end
  end
end
