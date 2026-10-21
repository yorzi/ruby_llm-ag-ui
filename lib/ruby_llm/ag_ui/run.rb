# frozen_string_literal: true

module RubyLLM
  module AgUI
    # Runs one RubyLLM 2.x chat turn as one AG-UI 1.0 run.
    #
    #   input = RubyLLM::AgUI::Input.parse(request_body)
    #   chat  = host_chat_for(actor, input.thread_id)   # host-owned RubyLLM::Chat
    #   RubyLLM::AgUI::Run.new(chat:, input:, scope: "tenant:#{actor.id}").stream(to: response.stream)
    #
    # The host owns authentication, authorization, the chat, the tools a run may
    # use and the transport. This class owns the run's identity (reserved before
    # any provider work), the ordering of the events, and the outcome: a
    # cancelled run is never reported as success, a provider failure is a
    # sanitized RUN_ERROR, a paused run is an interrupt rather than a success,
    # and an identity that is already reserved is never executed a second time.
    #
    # +scope+ is the host's tenant/actor boundary, built from authenticated
    # identity. The gem takes it from the host rather than deriving it from the
    # input, because a scope derived from anything the client sent would let one
    # client attach to another's run.
    class Run
      # The reserved record or final outcome observed by this run, including a
      # reconnect. Nil before the run obtains its reservation.
      attr_reader :record

      # rubocop:disable-next Metrics/ParameterLists -- one keyword per host-supplied or overridable value
      def initialize(chat:, input:, scope:, store: nil, logger: nil, redact: nil, clock: nil, expires_in: nil,
                     state: nil, emit_tool_progress: RubyLLM::AgUI.config.emit_tool_progress)
        defaults = RubyLLM::AgUI.config
        @chat = chat
        @input = input
        @scope = scope
        @store = store || defaults.run_store!
        @logger = logger || defaults.logger
        @redact = redact
        @clock = clock || defaults.clock
        @expires_in = expires_in || defaults.interrupt_ttl
        @emit_tool_progress = emit_tool_progress
        @mutex = Mutex.new
        validate!
        @state = state.nil? ? @input.state : state
      end

      # Reserves the run and streams it to +to+, an IO-like stream. Returns the
      # run's record, which carries the status the run ended with.
      #
      # The reservation happens before any provider work: a request whose input
      # digest matches an identity already reserved attaches instead of
      # executing, and a changed input under the same key is refused by the
      # store. A reserved run that already ended is served as a reconnect — its
      # outcome and state snapshot — never as a second execution.
      def stream(to:)
        resume.plan(now: @clock.call) if resume.needed?
        reservation = reserve
        @record = reservation.record
        return execute(@record, to) if reservation.created?

        reconnect(@record, to)
      end

      private

      def resume = @resume ||= Resume.new(input: @input, store: @store, scope: @scope, chat: @chat)

      def reserve
        Persistence.write do
          @store.reserve(scope: @scope, thread_id: @input.thread_id, run_id: @input.run_id, digest: @input.digest)
        end
      end

      # An identity that is already reserved is never executed a second time.
      # A run that ended is served as a reconnect: its outcome and state
      # snapshot, without replaying the deltas or running anything again.
      #
      # A run that has not ended cannot be served here. A second stream cannot
      # join a live one without a relay the gem does not own, and pretending it
      # did would either hang or duplicate the work, so it fails closed.
      def reconnect(record, to)
        unless Reconnect.serves?(record)
          raise StreamError, "run #{record.run_id} on thread #{record.thread_id} is still #{record.status}; " \
                             'a live run cannot be joined by a second stream'
        end

        build_emitter(record, to).replay(Reconnect.new(record: record, input: @input).events)
      end

      def execute(record, to)
        start_execution(record, to)
        resume.apply(now: @clock.call) if resume.needed?
        drive
        @record = finalize { finish }
      rescue RubyLLM::CancelledError
        @record = finalize { @emitter.cancel }
      rescue PersistenceError, RunConflictError
        raise
      rescue StandardError => e
        @record = finalize { @emitter.fail(e) }
      ensure
        finalize { @mapper&.close }
      end

      def start_execution(record, to)
        @mapper = build_mapper(record)
        @mapper.continue_tool_calls(@chat.pending_approvals.map(&:id)) if resume.needed?
        @emitter = build_emitter(record, to, mapper: @mapper)
        @emitter.start(run_started_event(record), state: @state)
      end

      def build_emitter(record, to, mapper: build_mapper(record))
        Emitter.new(
          writer: SSEWriter.new(to, logger: @logger), mapper: mapper, store: @store,
          record: record, clock: @clock, logger: @logger
        )
      end

      # Drives RubyLLM and projects what it reports.
      #
      # RubyLLM runs a host's local tools concurrently when asked to
      # (`tool_concurrency`), so `before_tool_call` can arrive from several
      # threads at once. The mapper is per-run state, so mapping and writing
      # happen under one lock: two callbacks never interleave inside it, and the
      # run's sequence stays a single ordered list.
      def drive
        @chat.before_tool_call { |tool_call| project { @mapper.before_tool_call(tool_call) } }
        @chat.after_message { |message| project { @mapper.message(message) } }
        if @emit_tool_progress == true
          @chat.after_tool_progress { |call, progress| project { @mapper.tool_progress(call, progress) } }
        end
        @chat.complete { |chunk| project { @mapper.chunk(chunk) } }
      end

      def finalize(&) = @mutex.synchronize(&)

      def project
        @mutex.synchronize { @emitter.write(yield) }
      end

      # A run that stopped for a human is an interrupt, never a success. Any
      # other pause is something this producer cannot express on the wire, so it
      # is a failure with a fixed, safe message rather than a run reported as
      # finished.
      def finish
        return @emitter.succeed unless @chat.waiting?
        raise UnsupportedRunStateError unless @chat.awaiting_approval?

        @emitter.interrupt(build_interrupts)
      end

      # One interrupt per pending approval, carrying the tool call, the digest of
      # the arguments RubyLLM asked to run, and a host-owned expiry. The host
      # still re-authorizes before the tool executes: an approval answers an
      # interrupt, it never grants a permission.
      def build_interrupts
        expires_at = @clock.call + @expires_in
        @chat.pending_approvals.map do |tool_call|
          Interrupt.create(
            tool_call_id: tool_call.id,
            arguments_digest: Canonical.digest(tool_call.arguments),
            expires_at: expires_at,
            message: "Approve the #{tool_call.name} tool call?"
          )
        end
      end

      def build_mapper(record)
        Mapper.new(thread_id: record.thread_id, run_id: record.run_id, redact: @redact, logger: @logger)
      end

      def run_started_event(record)
        Protocol.run_started(
          thread_id: record.thread_id, run_id: record.run_id, parent_run_id: @input.parent_run_id, input: @input.to_h
        )
      end

      def validate!
        unless @chat.respond_to?(:complete)
          raise ConfigurationError, 'chat must be a RubyLLM::Chat or act like one (it does not respond to #complete)'
        end
        raise ConfigurationError, 'input must be a RubyLLM::AgUI::Input' unless @input.is_a?(Input)

        return if @scope.is_a?(String) && !@scope.empty?

        raise ConfigurationError, Store::Base::SCOPE_MESSAGE
      end
    end
  end
end
