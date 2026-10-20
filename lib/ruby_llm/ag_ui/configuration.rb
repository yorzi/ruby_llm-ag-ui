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
    # Run.new can override storage, logging, redaction, clock, interrupt expiry,
    # and tool progress. Input.parse uses the configured request limits.
    class Configuration
      # The object that reserves run identity and stores interrupts. Defaults
      # to nil; set a RubyLLM::AgUI::Store::MemoryStore for single-process use,
      # or a durable store for multi-process deployment.
      attr_accessor :run_store

      # A callable (kind, payload) — or (payload) — invoked before a tool result
      # or activity payload reaches the wire. Return the value to publish.
      #
      # It defaults to RubyLLM::AgUI::Redaction.default, which keeps the
      # payload's shape and withholds its content: the gem cannot know which
      # part of a tool result is a secret, so it does not publish the raw value
      # until a host says it is safe. Opt out with
      # RubyLLM::AgUI::Redaction.method(:none), or replace it with your policy.
      attr_writer :redact

      # Whether runs publish local tool progress as activity snapshots. Off
      # unless the host opts in; progress payloads still pass through redaction.
      attr_accessor :emit_tool_progress

      # A Logger used for host-side diagnostics. Never receives prompts, raw
      # tool payloads or credentials.
      attr_accessor :logger

      # The AG-UI protocol version this producer speaks, emitted on
      # RUN_STARTED so a consumer can detect a downgrade.
      attr_reader :protocol_version

      # Accepts only the protocol implemented by this producer. A different
      # version is refused instead of silently reporting a misleading setting.
      def protocol_version=(value)
        unless value == Protocol::PROTOCOL_VERSION
          raise ConfigurationError, "This producer supports protocol #{Protocol::PROTOCOL_VERSION} only."
        end

        @protocol_version = value
      end

      # Maximum accepted request body size in bytes.
      attr_accessor :max_input_bytes

      # Maximum number of messages accepted in RunAgentInput.
      attr_accessor :max_messages

      # Maximum number of tools accepted in RunAgentInput.
      attr_accessor :max_tools

      # Maximum number of context entries accepted in RunAgentInput.
      attr_accessor :max_context

      # How long an interrupt stays answerable, in seconds.
      attr_accessor :interrupt_ttl

      # A callable returning the current UTC Time. Injected in tests.
      attr_accessor :clock

      def initialize
        @run_store = nil
        @redact = Redaction.method(:default)
        @logger = nil
        @protocol_version = Protocol::PROTOCOL_VERSION
        @max_input_bytes = 256_000
        @max_messages = 500
        @max_tools = 64
        @max_context = 64
        @interrupt_ttl = 900
        @clock = -> { Time.now.utc }
        @emit_tool_progress = false
      end

      # The redaction policy in force. Never nil: an unset or nil policy falls
      # back to the default rather than publishing raw payloads.
      def redact
        @redact || Redaction.method(:default)
      end

      # Which policy is in force, for diagnostics: :default, :none or :custom.
      def redaction
        return :default if redact == Redaction.method(:default)
        return :none if redact == Redaction.method(:none)

        :custom
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
          redact: redaction,
          protocol_version: protocol_version,
          max_input_bytes: max_input_bytes,
          max_messages: max_messages,
          max_tools: max_tools,
          max_context: max_context,
          interrupt_ttl: interrupt_ttl,
          emit_tool_progress: emit_tool_progress
        }
      end
    end
  end
end
