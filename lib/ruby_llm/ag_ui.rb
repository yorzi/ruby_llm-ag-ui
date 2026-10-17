# frozen_string_literal: true

require 'ruby_llm'
require 'ag_ui_protocol'
require 'zeitwerk'
require 'json'
require 'digest'
require 'securerandom'
require 'time'

require_relative 'ag_ui/version'

# RubyLLM::AgUI is an unofficial RubyLLM ecosystem extension that runs one
# RubyLLM 2.x chat turn as one AG-UI 1.0 run. Require it with:
#
#   require 'ruby_llm/ag_ui'
#
# The core is pure Ruby. Requiring this file does not load Rails, open a
# network connection, or read provider credentials. The Rails adapter lives
# under RubyLLM::AgUI::Rails and loads only when Rails is present.
module RubyLLM
  # The AG-UI integration namespace. Inside this namespace the protocol SDK is
  # referred to as ::AgUiProtocol and the Rails framework as ::Rails, because
  # RubyLLM::AgUI::Rails would otherwise shadow them.
  module AgUI
    class << self
      # Yields the memoized configuration.
      #
      #   RubyLLM::AgUI.configure do |config|
      #     config.run_store = MyRunStore.new
      #   end
      def configure
        yield config
      end

      # The memoized RubyLLM::AgUI::Configuration.
      def config
        @config ||= Configuration.new
      end

      # Replaces the configuration with defaults. Intended for tests.
      def reset_configuration!
        @config = Configuration.new
      end
    end
  end
end

loader = Zeitwerk::Loader.new
loader.tag = 'ruby_llm-ag_ui'
loader.inflector.inflect('sse' => 'SSE', 'ag_ui' => 'AgUI', 'ui' => 'UI', 'api' => 'API')
loader.push_dir(File.expand_path('ag_ui', __dir__), namespace: RubyLLM::AgUI)
# Errors are part of the boot contract: hosts rescue them without a lazy load.
loader.ignore(File.expand_path('ag_ui/error.rb', __dir__))
# The Rails adapter is not part of the pure-Ruby core. It is loaded by its
# railtie when Rails is present, or explicitly by the host.
loader.ignore(File.expand_path('ag_ui/rails', __dir__))
loader.setup

require_relative 'ag_ui/error'

require_relative 'ag_ui/rails/railtie' if defined?(Rails::Railtie)
