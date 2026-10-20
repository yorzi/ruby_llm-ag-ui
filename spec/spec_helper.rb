# frozen_string_literal: true

if ENV['COVERAGE']
  require 'simplecov'
  SimpleCov.start do
    add_filter '/spec/'
    add_filter '/examples/'
  end
end

# 'English' is capitalized: on a case-sensitive filesystem (CI's Linux)
# 'english' does not resolve to the stdlib.
require 'English'
require 'ruby_llm/ag_ui'
require 'webmock/rspec'

if ENV['RUBY_LLM_LIVE'] == '1'
  WebMock.disable_net_connect!(allow: %r{\Ahttps://openrouter\.ai/api/v1/chat/completions\z})
else
  WebMock.disable_net_connect!
end

Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |file| require file }

RSpec.configure do |config|
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  config.after { RubyLLM::AgUI.reset_configuration! }
end
