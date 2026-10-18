# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/migration'

module RubyLLM
  module AgUI
    module Generators
      # `bin/rails generate ruby_llm:ag_ui:install`
      #
      # Creates the table the durable run store keeps run identity in, and an
      # initializer that points the gem at it. Running it twice does nothing the
      # second time, because a migration and an initializer are files, not
      # state.
      class InstallGenerator < ::Rails::Generators::Base
        include ::Rails::Generators::Migration

        namespace 'ruby_llm:ag_ui:install'
        desc 'Create the ruby_llm-ag_ui run store table and its initializer.'
        source_root File.expand_path('templates', __dir__)

        def self.next_migration_number(dirname)
          ::ActiveRecord::Generators::Base.next_migration_number(dirname)
        end

        def create_migration_file
          migration_template 'create_ruby_llm_ag_ui_runs.rb.tt',
                             'db/migrate/create_ruby_llm_ag_ui_runs.rb'
        end

        def create_initializer
          template 'initializer.rb.tt', 'config/initializers/ruby_llm_ag_ui.rb'
        end
      end
    end
  end
end
