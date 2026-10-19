# frozen_string_literal: true

module RubyLLM
  module AgUI
    # :nodoc: Keep uncertain write acknowledgements separate from run outcomes.
    module Persistence
      module_function

      def write
        yield
      rescue Error
        raise
      rescue StandardError => e
        raise PersistenceError, "The store write could not be acknowledged: #{e.class}"
      end
    end
  end
end
