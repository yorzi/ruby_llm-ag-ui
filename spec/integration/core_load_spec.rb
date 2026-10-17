# frozen_string_literal: true

LIB_PATH = File.expand_path('../../lib', __dir__)
PROBE = <<~RUBY
  require 'ruby_llm/ag_ui'
  %w[Rails ActionController ActiveSupport ActiveRecord ActionCable].each do |name|
    abort "Rails was loaded: \#{name}" if Object.const_defined?(name)
  end
  abort 'top-level AgUi was defined' if Object.const_defined?(:AgUi)
  abort 'core constant missing' unless defined?(RubyLLM::AgUI::Configuration)
  abort 'protocol constant missing' unless defined?(RubyLLM::AgUI::Protocol::CancelledOutcome)
  puts 'ok'
RUBY

RSpec.describe 'requiring the core (FR-01)', type: :integration do
  def run_probe(script)
    IO.popen([RbConfig.ruby, '-I', LIB_PATH, '-e', script], err: %i[child out], &:read)
  end

  it 'loads without Rails, without top-level AgUi, and defines the core' do
    output = run_probe(PROBE)
    expect($CHILD_STATUS).to be_success, output
    expect(output).to include('ok')
  end

  it 'reports the gem version' do
    expect(RubyLLM::AgUI::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end
end
