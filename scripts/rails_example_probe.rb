# frozen_string_literal: true

# Run only inside the disposable installed-package host, after its core probes.
require 'fileutils'

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end

Dir.mktmpdir('ag-ui-rails-models-') do |directory|
  generator = Rails::Generators.find_by_namespace('ruby_llm:install')
  generator.start(['--skip-active-storage'], destination_root: directory, quiet: true)
  migrations = File.join(directory, 'db/migrate')
  last = Dir[File.join(migrations, '*.rb')].map { |file| File.basename(file).split('_').first.to_i }.max
  example = File.join(AgUiDemo::ROOT, 'examples/rails_8')
  Dir[File.join(example, 'db/migrate/*.rb')].each_with_index do |file, index|
    name = File.basename(file).split('_', 2).last
    FileUtils.cp(file, File.join(migrations, "#{last + index + 1}_#{name}"))
  end
  ActiveRecord::Migration.verbose = false
  ActiveRecord::MigrationContext.new(migrations).migrate

  load File.join(directory, 'app/models/message.rb')
  load File.join(example, 'app/models/actor.rb')
  load File.join(example, 'app/models/chat.rb')
  model = RubyLLM::ActiveRecord::Model.create!(model_id: 'fixture', name: 'Fixture', provider: 'openai')
  first, second = %w[first second].map { |name| Actor.create!(name: name) }
  first_chat = first.chats.create!(ag_ui_thread_id: 'shared', ruby_llm_model_id: model.id)
  second_chat = second.chats.create!(ag_ui_thread_id: 'shared', ruby_llm_model_id: model.id)
  abort 'chat identity did not persist' unless first.chats.find_by!(ag_ui_thread_id: 'shared').id == first_chat.id
  abort 'actor-scoped chat identity collided' if first_chat.id == second_chat.id
  abort 'RubyLLM message association missing' unless first_chat.messages.klass == Message
  puts 'RAILS_EXAMPLE_MODELS_PASS: generated RubyLLM tables, ordered example migrations, actor-scoped persisted chats'
end
