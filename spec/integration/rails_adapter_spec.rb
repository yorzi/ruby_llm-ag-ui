# frozen_string_literal: true

ADAPTER_LIB_PATH = File.expand_path('../../lib', __dir__)

RSpec.describe 'the optional Rails adapter (FR-01)', type: :integration do
  # The probes load Rails first, the way a Rails app does: `require 'rails/all'`
  # in config/application.rb, then Bundler requires the gems. The adapter has to
  # be there by the time a controller names the concern.
  def run_probe(script)
    IO.popen([RbConfig.ruby, '-I', ADAPTER_LIB_PATH, '-e', script], err: %i[child out], &:read)
  end

  it 'loads the adapter when Rails is already loaded, and still defines no top-level AgUi' do
    output = run_probe(<<~RUBY)
      require 'rails'
      require 'action_controller/railtie'
      require 'active_record/railtie'
      require 'ruby_llm/ag_ui'
      abort 'streaming concern missing' unless defined?(RubyLLM::AgUI::Rails::Streaming)
      abort 'active record store missing' unless defined?(RubyLLM::AgUI::Rails::ActiveRecordStore)
      abort 'the core is gone' unless defined?(RubyLLM::AgUI::Run)
      abort 'top-level AgUi was defined' if Object.const_defined?(:AgUi)
      puts 'ok'
    RUBY

    expect($CHILD_STATUS).to be_success, output
    expect(output).to include('ok')
  end

  it 'boots a Rails app with the railtie, and does not load the store without Active Record' do
    output = run_probe(<<~RUBY)
      require 'rails'
      require 'action_controller/railtie'
      require 'ruby_llm/ag_ui'
      abort 'streaming concern missing' unless defined?(RubyLLM::AgUI::Rails::Streaming)
      abort 'the store loaded without Active Record' if defined?(RubyLLM::AgUI::Rails::ActiveRecordStore)
      class ProbeApp < Rails::Application
        config.eager_load = false
        config.secret_key_base = 'probe'
        config.logger = Logger.new(IO::NULL)
      end
      ProbeApp.initialize!
      puts 'ok'
    RUBY

    expect($CHILD_STATUS).to be_success, output
    expect(output).to include('ok')
  end
end
