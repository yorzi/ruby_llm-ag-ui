# frozen_string_literal: true

module RubyLLM
  module AgUI
    module Rails
      # Loads the optional Rails adapter, and nothing else.
      #
      # The core is pure Ruby and `require 'ruby_llm/ag_ui'` loads no Rails. This
      # file is required only when Rails is already present, and it loads the
      # adapter's parts in dependency order, skipping the Active Record store
      # when the host has no Active Record at all. Calling it twice is harmless.
      def self.setup!
        require_relative 'streaming'
        return unless defined?(::ActiveRecord::Base)

        require_relative 'active_record_store'
      end

      # The railtie that loads the adapter during boot.
      class Railtie < ::Rails::Railtie
        initializer 'ruby_llm.ag_ui' do
          RubyLLM::AgUI::Rails.setup!
        end
      end
    end
  end
end

RubyLLM::AgUI::Rails.setup!
