# frozen_string_literal: true

RSpec.describe RubyLLM::AgUI::ErrorSanitizer do
  describe '.sanitize' do
    {
      RubyLLM::UnauthorizedError => 'provider_unauthorized',
      RubyLLM::ForbiddenError => 'provider_forbidden',
      RubyLLM::RateLimitError => 'provider_rate_limited',
      RubyLLM::ContextLengthExceededError => 'context_length_exceeded',
      RubyLLM::ContentFilterError => 'content_filtered',
      RubyLLM::ServerError => 'provider_unavailable',
      RubyLLM::ServiceUnavailableError => 'provider_unavailable',
      RubyLLM::BadRequestError => 'provider_bad_request',
      RubyLLM::ToolCallParseError => 'tool_call_parse_error',
      RubyLLM::ModelNotFoundError => 'model_not_found'
    }.each do |klass, expected_code|
      it "classifies #{klass} as #{expected_code}" do
        message, code = described_class.sanitize(klass.new('secret: sk-live-oops'))
        expect(code).to eq(expected_code)
        expect(message).not_to include('secret', 'sk-live')
      end
    end

    it 'classifies any other RubyLLM error as a generic provider error' do
      _message, code = described_class.sanitize(RubyLLM::Error.new('raw provider body'))
      expect(code).to eq('provider_error')
    end

    it 'falls back for unknown errors without leaking their message' do
      error = Class.new(StandardError).new('password=hunter2 at /srv/app')
      message, code = described_class.sanitize(error)
      expect(code).to eq('internal_error')
      expect(message).to eq('The run failed before it could finish.')
      expect(message).not_to include('hunter2')
    end

    it 'never returns the raw exception text' do
      error = RubyLLM::BadRequestError.new('request body {\"api_key\":\"sk-123\"}')
      message, = described_class.sanitize(error)
      expect(message).not_to include('api_key', 'sk-123')
    end

    it 'classifies timeouts as transport errors' do
      _message, code = described_class.sanitize(Timeout::Error.new('timed out'))
      expect(code).to eq('transport_timeout')
    end
  end
end
