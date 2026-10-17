# frozen_string_literal: true

module RubyLLM
  module AgUI
    # Global configuration for the gem. Hosts usually set it once at boot:
    #
    #   RubyLLM::AgUI.configure do |config|
    #     config.run_store = MyRunStore.new
    #     config.redact    = ->(kind, payload) { MyRedactor.call(kind, payload) }
    #     config.logger    = Rails.logger
    #   end
    #
    # Every value can be overridden per run by passing the matching keyword to
    # RubyLLM::AgUI::Run.new.
    class Configuration
      # The object that reserves run identity and stores interrupts. Defaults
      # to nil; set a RubyLLM::AgUI::Store::MemoryStore for single-process use,
      # or a durable store for multi-process deployment.
      attr_accessor :run_store

      # A callable (kind, payload) invoked before tool results, state and
      # activity payloads reach the wire. Return the redacted payload. The
      # default keeps the payload unchanged; hosts should override it to strip
      # secrets and personal data.
      attr_accessor :redact

      # A Logger used for host-side diagnostics. Never receives prompts, raw
      # tool payloads or credentials.
      attr_accessor :logger

      # The AG-UI protocol version this producer speaks, emitted on
      # RUN_STARTED so a consumer can detect a downgrade.
      attr_accessor :protocol_version

      # Maximum accepted request body size in bytes.
      attr_accessor :max_input_bytes

      # Maximum number of messages accepted in RunAgentInput.
      attr_accessor :max_messages

      # Maximum number of tools accepted in RunAgentInput.
      attr_accessor :max_tools

      # Maximum number of context entries accepted in RunAgentInput.
      attr_accessor :max_context

      # Whether RubyLLM after_tool_progress callbacks are projected as AG-UI
      # activity events. Off by default: the mapping is only enabled when the
      # host has real, safe progress data to publish.
      attr_accessor :emit_tool_progress

      # How long an interrupt stays answerable, in seconds.
      attr_accessor :interrupt_ttl

      # A callable returning the current UTC Time. Injected in tests.
      attr_accessor :clock

      # Whether client-supplied message history is reconciled against
      # host-stored history. Always off in the first release: client messages
      # are never trusted as system or tool turns.
      attr_accessor :allow_client_history

      def initialize
        @run_store = nil
        @redact = nil
        @logger = nil
        @protocol_version = '1.0'
        @max_input_bytes = 256_000
        @max_messages = 500
        @max_tools = 64
        @max_context = 64
        @emit_tool_progress = false
        @interrupt_ttl = 900
        @clock = -> { Time.now.utc }
        @allow_client_history = false
      end

      # The run store, or nil when the host has not configured one.
      def run_store!
        @run_store || raise(ConfigurationError, 'No run_store is configured. ' \
                                                'Set RubyLLM::AgUI.config.run_store or pass store: to Run.new.')
      end

      # A snapshot of the configuration, for diagnostics and support reports.
      # Never includes secrets.
      def to_h
        {
          run_store: run_store&.class&.name,
          redact: !redact.nil?,
          protocol_version: protocol_version,
          max_input_bytes: max_input_bytes,
          max_messages: max_messages,
          max_tools: max_tools,
          max_context: max_context,
          emit_tool_progress: emit_tool_progress,
          interrupt_ttl: interrupt_ttl,
          allow_client_history: allow_client_history
        }
      end
    end
  end
end
