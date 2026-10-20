# frozen_string_literal: true

module RubyLLM
  module AgUI
    # Projects one RubyLLM 2.x chat turn onto AG-UI 1.0 events (FR-03).
    #
    # The mapper is the only place that decides which AG-UI event a RubyLLM
    # signal becomes. It is a state machine rather than a set of converters,
    # because the protocol's rules are about state: a text message must be open
    # before its content arrives, a tool call must be closed before its result,
    # consecutive steps must not overlap, and everything must be closed before
    # the run's terminal event.
    #
    # It maps what RubyLLM actually reported and nothing else. It never invents
    # an event to fill a gap in its own output, and it never re-synthesises tool
    # arguments that RubyLLM delivered as a stream: the deltas go out as
    # received, in order.
    #
    # Every method returns the events to write, in order. The mapper writes
    # nothing itself, so the caller owns the transport and can advance the run
    # record's sequence with the same list.
    #
    #   mapper = RubyLLM::AgUI::Mapper.new(thread_id: "t1", run_id: "r1")
    #
    #   chat.before_tool_call { |tool_call| write(mapper.before_tool_call(tool_call)) }
    #   chat.after_message    { |message|   write(mapper.message(message)) }
    #   chat.complete         { |chunk|     write(mapper.chunk(chunk)) }
    #
    #   write(mapper.close)  # before the run's terminal event
    class Mapper
      # The two phases a step delimits: one model round-trip that produces text
      # and/or tool calls, and the tool round that answers those calls. A step
      # ends as soon as a phase of the other kind begins, so consecutive steps
      # never overlap.
      STEP_COMPLETION = :completion
      STEP_TOOL = :tool

      # The AG-UI conversation this run belongs to.
      attr_reader :thread_id

      # Identifies this run. Every id the mapper mints is scoped to it, so two
      # runs on one thread never collide.
      attr_reader :run_id

      def initialize(thread_id:, run_id:, redact: nil, logger: nil)
        @thread_id = thread_id
        @run_id = run_id
        @redact = redact || RubyLLM::AgUI.config.redact
        @logger = logger || RubyLLM::AgUI.config.logger
        @message_count = 0
        @step_count = 0
        @open_text_id = nil
        @last_message_id = nil
        @text_emitted = false
        @calls = {}
        @completed_tools = {}
        @open_step = nil
        @step_kind = nil
        @warned_redaction = false
        @closed = false
      end

      # Internal resume bookkeeping: these calls were already reported by the
      # interrupted run. Only their result and progress belong to this run.
      def continue_tool_calls(ids) # :nodoc:
        @continued_tool_call_ids = ids.dup.freeze
      end

      # One streamed Chunk from Chat#complete.
      def chunk(chunk)
        return [] if @closed

        events = text_events(chunk.content)
        events.concat(tool_call_events(chunk.tool_calls, streamed: true))
        events.concat(close_events) if chunk.finish_reason
        events
      end

      # One Message appended to the conversation, from Chat#after_message.
      #
      # An assistant message ends the completion, so whatever the stream did not
      # carry is emitted here: a provider that did not stream, or a tool call it
      # reported only in the final message, still produces a valid AG-UI
      # sequence instead of a run that silently says nothing.
      def message(message)
        return [] if @closed
        return tool_result_events(message) if message.role == :tool

        assistant_events(message)
      end

      # A local ToolCall about to execute, from Chat#before_tool_call.
      #
      # Its arguments are complete, and its deltas have already gone out if the
      # provider streamed them, so this only opens a call the stream never
      # reported and closes the call so the client knows the arguments ended.
      def before_tool_call(tool_call)
        return [] if @closed

        events = tool_call_events({ tool_call.id => tool_call }, streamed: false)
        events.concat(close_tool_calls)
        events
      end

      # Reports a tool's actual progress as a replacing activity snapshot.
      # Each call has one run-scoped activity id. Values pass through the host's
      # :tool_progress redaction policy; the tool call id remains structural.
      # Empty updates and callbacks for finished tools or runs produce nothing.
      def tool_progress(tool_call, progress)
        return [] if @closed || @completed_tools[tool_call.id]

        payload = { 'value' => progress.value, 'total' => progress.total, 'message' => progress.message }.compact
        return [] if payload.empty?

        [::AgUiProtocol::Core::Events::ActivitySnapshotEvent.new(
          message_id: "#{@run_id}:progress:#{tool_call.id}", activity_type: 'TOOL_PROGRESS',
          content: { 'toolCallId' => tool_call.id, 'progress' => redact(Redaction::TOOL_PROGRESS, payload) },
          replace: true
        )]
      end

      # Closes any open text message, tool call and step, and closes the mapper.
      #
      # The caller writes these before the terminal event: AG-UI has no way to
      # close a run whose content is still open, and a client that never sees
      # TEXT_MESSAGE_END waits for a message that will not grow.
      #
      # Closing is final, and it is the reason a second turn on the same chat is
      # safe. RubyLLM's callbacks are additive: the callbacks this run registered
      # stay attached after the run ends, so the next `complete` on that chat
      # fires this mapper again. A closed mapper maps nothing — the content it
      # would open belongs to a run that is already over, and writing it would
      # report the previous run's ids and steps inside the next run's stream.
      def close
        @closed = true
        close_events
      end

      private

      # --- text ---------------------------------------------------------------

      def text_events(content)
        return [] if content.nil? || content.empty?

        events = open_text_events
        events << ::AgUiProtocol::Core::Events::TextMessageContentEvent.new(
          message_id: @open_text_id, delta: content
        )
        @text_emitted = true
        events
      end

      def open_text_events
        return [] if @open_text_id

        @open_text_id = new_message_id('a')
        @last_message_id = @open_text_id
        events = ensure_step(STEP_COMPLETION)
        events << ::AgUiProtocol::Core::Events::TextMessageStartEvent.new(
          message_id: @open_text_id, role: 'assistant'
        )
        events
      end

      def close_text_events
        return [] unless @open_text_id

        message_id = @open_text_id
        @open_text_id = nil
        [::AgUiProtocol::Core::Events::TextMessageEndEvent.new(message_id: message_id)]
      end

      # --- assistant message ---------------------------------------------------

      def assistant_events(message)
        events = []
        events.concat(text_events(message.content)) unless @text_emitted
        events.concat(close_text_events)
        events.concat(tool_call_events(message.tool_calls, streamed: false))
        events.concat(close_tool_calls)
        events.concat(close_step)
        @last_message_id = nil
        @text_emitted = false
        events
      end

      # --- tool calls ----------------------------------------------------------

      def tool_call_events(tool_calls, streamed:)
        return [] if tool_calls.nil? || tool_calls.empty?

        tool_calls.flat_map do |key, tool_call|
          next [] if @continued_tool_call_ids&.include?(tool_call.id)

          record = track(key, tool_call, streamed: streamed)
          open_tool_call(record) + argument_events(record, tool_call, streamed: streamed)
        end
      end

      # The record for one tool call, created on first sight.
      #
      # A streamed delta is keyed by index and carries the id only on its first
      # fragment; the complete message is keyed by id. Both keys point at the
      # same record, so the call is opened once.
      def track(key, tool_call, streamed:)
        record = @calls[key] || find_call(tool_call.id) || new_call
        record[:id] ||= tool_call.id
        record[:name] ||= tool_call.name
        record[:streamed] ||= streamed
        @calls[key] = record
        @calls[record[:id]] = record if record[:id]
        record
      end

      def new_call
        { id: nil, name: nil, streamed: false, args_emitted: false, started: false, closed: false, buffered: nil }
      end

      def find_call(id)
        id && @calls[id]
      end

      # Opens the call the first time its id and name are both known. A call
      # reported as arguments-only deltas stays buffered until its name arrives,
      # so no fragment of the provider's argument bytes is dropped.
      def open_tool_call(record)
        return [] if record[:started] || record[:id].nil? || record[:name].nil?

        record[:started] = true
        events = close_text_events
        events.concat(ensure_step(STEP_COMPLETION))
        events << ::AgUiProtocol::Core::Events::ToolCallStartEvent.new(
          tool_call_id: record[:id], tool_call_name: record[:name], parent_message_id: @last_message_id
        )
        events.concat(buffered_argument_events(record))
      end

      def buffered_argument_events(record)
        buffered = record[:buffered]
        record[:buffered] = nil
        return [] if buffered.nil? || buffered.empty?

        [::AgUiProtocol::Core::Events::ToolCallArgsEvent.new(tool_call_id: record[:id], delta: buffered)]
      end

      def argument_events(record, tool_call, streamed:)
        delta = argument_delta(record, tool_call, streamed: streamed)
        return [] if delta.nil? || delta.empty?
        return buffer_argument(record, delta) unless record[:started]

        [::AgUiProtocol::Core::Events::ToolCallArgsEvent.new(tool_call_id: record[:id], delta: delta)]
      end

      def buffer_argument(record, delta)
        record[:buffered] = (record[:buffered] || +'') + delta
        []
      end

      # A streamed chunk carries a fragment of the provider's own argument bytes
      # and goes out unchanged. A complete message carries the Hash RubyLLM
      # reconstructed from those bytes, so it is serialized once and only when
      # the stream did not already deliver the fragments.
      def argument_delta(record, tool_call, streamed:)
        return streamed_delta(tool_call) if streamed
        return nil if record[:streamed] || record[:args_emitted]

        record[:args_emitted] = true
        arguments = tool_call.arguments
        arguments.is_a?(String) ? arguments : Canonical.dump(arguments)
      end

      def streamed_delta(tool_call)
        arguments = tool_call.arguments
        arguments.is_a?(String) ? arguments : arguments.to_s
      end

      def close_tool_calls
        @calls.values.uniq.filter_map do |record|
          next if record[:closed] || !record[:started]

          record[:closed] = true
          ::AgUiProtocol::Core::Events::ToolCallEndEvent.new(tool_call_id: record[:id])
        end
      end

      # --- tool results --------------------------------------------------------

      def tool_result_events(message)
        @completed_tools[message.tool_call_id] = true
        events = close_text_events
        events.concat(close_tool_calls)
        events.concat(ensure_step(STEP_TOOL))
        events << ::AgUiProtocol::Core::Events::ToolCallResultEvent.new(
          message_id: "#{@run_id}:tool:#{message.tool_call_id}",
          tool_call_id: message.tool_call_id,
          content: redact(Redaction::TOOL_RESULT, message.content.to_s),
          role: 'tool'
        )
        @text_emitted = false
        events
      end

      # --- steps ---------------------------------------------------------------

      # Ensures the step for +kind+ is the open one, closing the previous step
      # first when the phase changed. Opening a step of the same kind is a no-op,
      # so the deltas of one completion stay inside a single step.
      def ensure_step(kind)
        return [] if @open_step && @step_kind == kind

        events = close_step
        @step_count += 1
        @open_step = "step-#{@step_count}"
        @step_kind = kind
        events << ::AgUiProtocol::Core::Events::StepStartedEvent.new(step_name: @open_step)
        events
      end

      def close_step
        return [] unless @open_step

        step_name = @open_step
        @open_step = nil
        @step_kind = nil
        [::AgUiProtocol::Core::Events::StepFinishedEvent.new(step_name: step_name)]
      end

      # --- closing -------------------------------------------------------------

      def close_events
        events = close_text_events
        events.concat(close_tool_calls)
        events.concat(close_step)
        events
      end

      # --- redaction -----------------------------------------------------------

      def redact(kind, payload)
        warn_about_redaction
        Redaction.apply(@redact, kind, payload)
      end

      def warn_about_redaction
        return unless @redact == Redaction.method(:default)
        return if @warned_redaction

        @warned_redaction = true
        @logger&.warn('[ruby_llm_ag_ui] tool results and progress are redacted by default; ' \
                      'configure RubyLLM::AgUI.config.redact to publish them')
      end

      def new_message_id(suffix)
        @message_count += 1
        "#{@run_id}:#{suffix}#{@message_count}"
      end
    end
  end
end
