# frozen_string_literal: true

# The live and intercepted-HTTP suites use the same provider setup. No key is
# read until an explicitly opted-in test constructs the default configuration.
module LiveHarness
  class FixtureLookup < RubyLLM::Tool
    description 'Return a synthetic fixture value without accessing any external system.'
    parameter :value, description: 'The exact fixture value requested by the user.'
    requires_approval

    attr_reader :calls

    def initialize
      super
      @calls = 0
    end

    def execute(value:)
      @calls += 1
      { value: value, private_detail: 'fixture-secret' }
    end
  end

  module_function

  def configuration
    RubyLLM::Configuration.new.tap do |config|
      config.openrouter_api_key = ENV.fetch('OPENROUTER_API_KEY')
      config.max_retries = 0
      config.request_timeout = 30
      config.logger = Logger.new(IO::NULL)
    end
  end

  def chat(prompt:, tool: nil, configuration: self.configuration)
    model = ENV.fetch('RUBY_LLM_LIVE_MODEL', 'openai/gpt-4.1-mini')
    RubyLLM::Context.new(configuration).chat(model: model, provider: :openrouter,
                                             assume_model_exists: true).tap do |instance|
      instance.with_temperature(0).with_max_output_tokens(128)
      instance.with_tools(tool).with_tool_options(choice: tool.name) if tool
      instance.add_message(role: :user, content: prompt)
    end
  end
end
