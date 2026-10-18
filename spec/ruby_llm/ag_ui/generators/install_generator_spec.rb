# frozen_string_literal: true

require 'rails_helper'
require 'rails/generators'
require 'generators/ruby_llm/ag_ui/install_generator'

RSpec.describe RubyLLM::AgUI::Generators::InstallGenerator do
  it 'is reachable as `bin/rails generate ruby_llm:ag_ui:install`' do
    expect(Rails::Generators.find_by_namespace('ruby_llm:ag_ui:install')).to eq(described_class)
  end

  it 'ships the migration and the initializer it installs' do
    %w[create_ruby_llm_ag_ui_runs.rb.tt initializer.rb.tt].each do |template|
      expect(File).to exist(File.join(described_class.source_root, template))
    end
  end

  it 'creates the table the store reads, with the identity index it relies on' do
    migration = File.read(File.join(described_class.source_root, 'create_ruby_llm_ag_ui_runs.rb.tt'))

    expect(migration).to include('create_table :ruby_llm_ag_ui_runs')
    expect(migration).to include('add_index :ruby_llm_ag_ui_runs, %i[scope thread_id run_id], unique: true')
    %w[scope thread_id run_id digest status sequence payload].each do |column|
      expect(migration).to include(":#{column}")
    end
    # JSON text, not a database JSON type: the gem owns the encoding.
    expect(migration).to include('t.text :payload')
  end

  it 'points the host at the durable store it just installed' do
    initializer = File.read(File.join(described_class.source_root, 'initializer.rb.tt'))

    expect(initializer).to include('RubyLLM::AgUI.configure')
    expect(initializer).to include('config.run_store = RubyLLM::AgUI::Rails::ActiveRecordStore.new')
  end

  it 'targets the Rails version the host is running, not a pinned one' do
    migration = File.read(File.join(described_class.source_root, 'create_ruby_llm_ag_ui_runs.rb.tt'))

    # A hardcoded [7.1] silently downgrades every host that generates it.
    expect(migration).to include('ActiveRecord::Migration[<%= ActiveRecord::Migration.current_version %>]')
  end
end
