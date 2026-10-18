# frozen_string_literal: true

require 'tmpdir'
require_relative 'host'

module AgUiDemo
  # One disposable host for both real HTTP/browser and installed-package probes.
  def self.with_host
    Dir.mktmpdir('ag-ui-demo-') do |temporary|
      ENV['DATABASE_URL'] = "sqlite3:#{File.join(temporary, 'runs.sqlite3')}"
      Application.initialize!
      Application.routes.draw { post '/agent', to: 'ag_ui_demo/runs#create' }
      migrate(temporary)
      configure
      yield Host.new
    ensure
      ActiveRecord::Base.connection_pool.disconnect!
    end
  end

  def self.migrate(temporary)
    require 'rails/generators'
    require 'rails/generators/active_record'
    Rails::Generators.find_by_namespace('ruby_llm:ag_ui:install').start([], destination_root: temporary, quiet: true)
    load Dir[File.join(temporary, 'db/migrate/*.rb')].fetch(0)
    CreateRubyLlmAgUiRuns.new.suppress_messages { CreateRubyLlmAgUiRuns.new.migrate(:up) }
  end

  def self.configure
    RubyLLM::AgUI.configure do |config|
      config.run_store = RubyLLM::AgUI::Rails::ActiveRecordStore.new
      config.emit_tool_progress = true
      # Only synthetic counts are public; results and progress messages stay private.
      config.redact = lambda do |kind, payload|
        kind == :tool_progress ? payload.slice('value', 'total') : RubyLLM::AgUI::Redaction.default(kind, payload)
      end
    end
  end
end
