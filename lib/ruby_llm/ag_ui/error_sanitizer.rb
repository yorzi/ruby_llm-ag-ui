# frozen_string_literal: true

module RubyLLM
  module AgUI
    # Turns an exception into a safe (message, code) pair for RUN_ERROR.
    #
    # Upstream Rails examples put `e.message` straight into RUN_ERROR, which
    # can leak prompts, request bodies, API keys and internal paths. This
    # module never does that: it classifies the error by class and returns a
    # fixed, public message. The raw exception goes to the host logger, if the
    # host configured one, and nowhere else.
    module ErrorSanitizer
      # Ordered by specificity. The first ancestor of the error whose name is a
      # key wins, so subclass relationships are respected without loading
      # optional error classes eagerly.
      MESSAGES = {
        'RubyLLM::UnauthorizedError' => ['The model provider rejected the request.', 'provider_unauthorized'],
        'RubyLLM::ForbiddenError' => ['The model provider refused the request.', 'provider_forbidden'],
        'RubyLLM::PaymentRequiredError' => ['The model provider account needs attention.', 'provider_payment_required'],
        'RubyLLM::RateLimitError' => ['The model provider rate limit was reached.', 'provider_rate_limited'],
        'RubyLLM::ContextLengthExceededError' => [
          'The conversation exceeded the model context window.', 'context_length_exceeded'
        ],
        'RubyLLM::ContentFilterError' => ['The model provider filtered the response.', 'content_filtered'],
        'RubyLLM::OverloadedError' => ['The model provider is temporarily unavailable.', 'provider_unavailable'],
        'RubyLLM::ServiceUnavailableError' => [
          'The model provider is temporarily unavailable.', 'provider_unavailable'
        ],
        'RubyLLM::ServerError' => ['The model provider is temporarily unavailable.', 'provider_unavailable'],
        'RubyLLM::BadRequestError' => ['The model provider rejected the request shape.', 'provider_bad_request'],
        'RubyLLM::InvalidToolChoiceError' => ['The requested tool choice is not available.', 'invalid_tool_choice'],
        'RubyLLM::ToolCallParseError' => ['The model produced an unparseable tool call.', 'tool_call_parse_error'],
        'RubyLLM::UnsupportedAttachmentError' => ['An attachment could not be sent.', 'unsupported_attachment'],
        'RubyLLM::ModelNotFoundError' => ['The model is not available.', 'model_not_found'],
        'RubyLLM::Error' => ['The model provider returned an error.', 'provider_error'],
        'Faraday::Error' => ['The model provider request failed.', 'transport_error'],
        'Timeout::Error' => ['The model provider request timed out.', 'transport_timeout'],
        'Errno::ETIMEDOUT' => ['The model provider request timed out.', 'transport_timeout']
      }.freeze

      FALLBACK = ['The run failed before it could finish.', 'internal_error'].freeze

      module_function

      # Returns a [message, code] pair safe to put on the wire.
      def sanitize(error)
        match = classify(error)
        match || FALLBACK
      end

      # Returns the [message, code] pair for +error+, falling back to FALLBACK.
      def classify(error)
        names = error.class.ancestors.map(&:name).compact
        names.each do |name|
          entry = MESSAGES[name]
          return entry if entry
        end
        nil
      end
    end
  end
end
