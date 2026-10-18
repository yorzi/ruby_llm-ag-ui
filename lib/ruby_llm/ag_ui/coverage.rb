# frozen_string_literal: true

module RubyLLM
  module AgUI
    # The AG-UI 1.0 producer coverage map (FR-02).
    #
    # Every one of the 31 event types the pinned 1.0 schema defines is listed
    # with the status this gem gives it. A producer is not required to
    # manufacture events it has no data for; what it must never do is emit an
    # event that the schema does not define, or misreport one it does.
    #
    # This is the gem's own audit against the pinned schema commit
    # (RubyLLM::AgUI::Protocol::SCHEMA_COMMIT). It is not a claim about
    # `ag-ui-protocol`, whose enum is compared separately below.
    module Coverage
      # The statuses an entry may have.
      #   :produced     — emitted from real RubyLLM data on the supported path
      #   :optional     — emitted only when the host opts in and real data exists
      #   :host_owned   — the host owns the payload; the gem does not produce it
      #   :not_produced — the producer has no data for it and never fabricates it
      STATUSES = %i[produced optional host_owned not_produced].freeze

      # Event types listed in the pinned docs/spec/1.0/schema.json Event union.
      SCHEMA_EVENT_TYPES = %w[
        TEXT_MESSAGE_START TEXT_MESSAGE_CONTENT TEXT_MESSAGE_END TEXT_MESSAGE_CHUNK
        TOOL_CALL_START TOOL_CALL_ARGS TOOL_CALL_END TOOL_CALL_CHUNK TOOL_CALL_RESULT
        STATE_SNAPSHOT STATE_DELTA MESSAGES_SNAPSHOT
        ACTIVITY_SNAPSHOT ACTIVITY_DELTA
        RAW CUSTOM
        RUN_STARTED RUN_FINISHED RUN_ERROR STEP_STARTED STEP_FINISHED
        REASONING_START REASONING_MESSAGE_START REASONING_MESSAGE_CONTENT
        REASONING_MESSAGE_END REASONING_MESSAGE_CHUNK REASONING_END REASONING_ENCRYPTED_VALUE
        SUBAGENT_STARTED SUBAGENT_FINISHED SUBAGENT_ERROR
      ].freeze

      FAMILIES = {
        'TEXT_MESSAGE' => :text_messages,
        'TOOL_CALL' => :tool_calls,
        'STATE' => :state,
        'MESSAGES' => :state,
        'ACTIVITY' => :activity,
        'RAW' => :raw_custom,
        'CUSTOM' => :raw_custom,
        'RUN' => :run_lifecycle,
        'STEP' => :run_lifecycle,
        'REASONING' => :reasoning,
        'SUBAGENT' => :subagents
      }.freeze

      # Producer status and a one-line reason, keyed by event type.
      STATUS = {
        'RUN_STARTED' => [:produced, 'Opens a reserved run; declares protocolVersion.'],
        'RUN_FINISHED' => [:produced, 'Success, interrupt or cancelled outcome; never a raw partial.'],
        'RUN_ERROR' => [:produced, 'Sanitized message and code; never raw exception text.'],
        'STEP_STARTED' => [:produced, 'One step per RubyLLM completion or tool round.'],
        'STEP_FINISHED' => [:produced, 'Closed before the terminal event.'],
        'TEXT_MESSAGE_START' => [:produced, 'Opened on the first streamed assistant text chunk.'],
        'TEXT_MESSAGE_CONTENT' => [:produced, 'One delta per non-empty chunk.content.'],
        'TEXT_MESSAGE_END' => [:produced, 'Closed before a tool round or the terminal event.'],
        'TEXT_MESSAGE_CHUNK' => [:not_produced, 'Convenience form; the gem emits the explicit triad.'],
        'TOOL_CALL_START' => [:produced, 'Emitted when a call is observed before it runs.'],
        'TOOL_CALL_ARGS' => [:produced, 'Arguments as received; never re-synthesized.'],
        'TOOL_CALL_END' => [:produced, 'Closed before the call runs or the run ends.'],
        'TOOL_CALL_RESULT' => [:produced, 'Tool result after the host redaction policy.'],
        'TOOL_CALL_CHUNK' => [:not_produced, 'Convenience form; the gem emits the explicit triad.'],
        'MESSAGES_SNAPSHOT' => [:host_owned, 'Not produced: history is the host\'s; ids are never re-synthesized.'],
        'STATE_SNAPSHOT' => [:produced, 'Reconnect: the state the host gave the run, never replayed deltas.'],
        'STATE_DELTA' => [:host_owned, 'Not produced: patches are the host\'s to describe; the gem invents none.'],
        'ACTIVITY_SNAPSHOT' => [:not_produced, 'No ACTIVITY_* projection yet; after_tool_progress is not mapped.'],
        'ACTIVITY_DELTA' => [:not_produced, 'No ACTIVITY_* projection yet; the gem does not invent patches.'],
        'REASONING_START' => [:not_produced, 'Private reasoning is not emitted until a host opts in.'],
        'REASONING_MESSAGE_START' => [:not_produced, 'Never emitted; a chunk that carries thinking is ignored.'],
        'REASONING_MESSAGE_CONTENT' => [:not_produced, 'Never emitted; a chunk that carries thinking is ignored.'],
        'REASONING_MESSAGE_END' => [:not_produced, 'Never emitted; nothing opens a reasoning block to close.'],
        'REASONING_MESSAGE_CHUNK' => [:not_produced, 'Convenience form; not emitted.'],
        'REASONING_END' => [:not_produced, 'Never emitted; nothing opens a reasoning block to close.'],
        'REASONING_ENCRYPTED_VALUE' => [:not_produced, 'No encrypted reasoning source in RubyLLM 2.x.'],
        'RAW' => [:not_produced, 'The gem never passes provider payloads through.'],
        'CUSTOM' => [:optional, 'Only safe, documented host extensions.'],
        'SUBAGENT_STARTED' => [:not_produced, 'RubyLLM 2.x runs one chat; no subagent data exists.'],
        'SUBAGENT_FINISHED' => [:not_produced, 'RubyLLM 2.x runs one chat; no subagent data exists.'],
        'SUBAGENT_ERROR' => [:not_produced, 'RubyLLM 2.x runs one chat; no subagent data exists.']
      }.freeze

      # The 1.0 shapes `ag-ui-protocol` 0.2.0 cannot express, with the gem's
      # handling. Upstream issues are drafted in docs/upstream; file them there.
      GAPS = [
        {
          id: 'SDK-GAP-01',
          shape: 'RunFinishedCancelledOutcome',
          detail: 'ag-ui-protocol 0.2.0 has success and interrupt outcomes only.',
          gem_handling: 'RubyLLM::AgUI::Protocol::CancelledOutcome, a schema-valid "cancelled" outcome.',
          upstream: 'https://github.com/ag-ui-protocol/ag-ui/issues'
        },
        {
          id: 'SDK-GAP-02',
          shape: 'RUN_STARTED.protocolVersion',
          detail: "0.2.0's RunStartedEvent has no protocolVersion field.",
          gem_handling: 'RubyLLM::AgUI::Protocol::RunStartedEvent adds it, defaulting to "1.0".',
          upstream: 'https://github.com/ag-ui-protocol/ag-ui/issues'
        },
        {
          id: 'SDK-GAP-03',
          shape: 'JSON to RunAgentInput parser',
          detail: '0.2.0 models have constructors and to_h only; there is no inbound parser.',
          gem_handling: 'RubyLLM::AgUI::Input.parse with size and schema bounds.',
          upstream: 'https://github.com/ag-ui-protocol/ag-ui/issues'
        },
        {
          id: 'SDK-GAP-04',
          shape: 'SUBAGENT_STARTED / _FINISHED / _ERROR',
          detail: 'The five legacy THINKING constants are present; the three SUBAGENT types are not.',
          gem_handling: 'Not produced: RubyLLM 2.x runs a single chat with no subagent data.',
          upstream: 'https://github.com/ag-ui-protocol/ag-ui/issues'
        }
      ].freeze

      # Event types present in the SDK enum but not in the 1.0 schema (the five
      # legacy THINKING constants). Emitting one would masquerade as 1.0.
      LEGACY_SDK_ONLY = %w[
        THINKING_TEXT_MESSAGE_START THINKING_TEXT_MESSAGE_CONTENT THINKING_TEXT_MESSAGE_END
        THINKING_START THINKING_END
      ].freeze

      module_function

      # Every schema event type with its family and status, as an array of
      # hashes suitable for docs generation.
      def entries
        SCHEMA_EVENT_TYPES.map do |type|
          status, note = STATUS.fetch(type)
          { type: type, family: family_for(type), status: status, note: note }
        end
      end

      # The family an event type belongs to.
      def family_for(type)
        prefix = FAMILIES.keys.find { |key| type.start_with?(key) }
        FAMILIES.fetch(prefix)
      end

      # Event types grouped by status.
      def report
        entries.group_by { |entry| entry[:status] }
      end

      # Event type constants the SDK defines (read at runtime, not hardcoded).
      def sdk_event_types
        ::AgUiProtocol::Core::Events::EventType.constants.map { |name| ::AgUiProtocol::Core::Events::EventType.const_get(name) }
      end

      # SDK constants with no 1.0 schema counterpart.
      def sdk_only_event_types
        sdk_event_types - SCHEMA_EVENT_TYPES
      end

      # 1.0 schema types with no SDK constant.
      def schema_only_event_types
        SCHEMA_EVENT_TYPES - sdk_event_types
      end
    end
  end
end
