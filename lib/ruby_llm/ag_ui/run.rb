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
      # The run's authoritative record, once it has been reserved.
      attr_reader :record

      # rubocop:disable-next Metrics/ParameterLists -- one keyword per host-supplied or overridable value
      def initialize(chat:, input:, scope:, store: nil, logger: nil, redact: nil, clock: nil, expires_in: nil)
        @chat = chat
        @input = input
        @scope = scope
        @store = store || RubyLLM::AgUI.config.run_store!
        @logger = logger || RubyLLM::AgUI.config.logger
        @redact = redact
        @clock = clock || RubyLLM::AgUI.config.clock
        @expires_in = expires_in || RubyLLM::AgUI.config.interrupt_ttl
        @mutex = Mutex.new
        validate!
      end

      # Reserves the run and streams it to +to+, an IO-like stream. Returns the
      # run's record, which carries the status the run ended with.
      #
      # The reservation happens before any provider work: a duplicate request
      # whose input digest matches attaches instead of executing, and a changed
      # input under the same key is refused by the store.
      def stream(to:)
        reservation = reserve
        return execute(reservation.record, to) if reservation.created?

        refuse_duplicate(reservation.record)
      end

      private

      def reserve
        @store.reserve(
          scope: @scope, thread_id: @input.thread_id, run_id: @input.run_id, digest: @input.digest
        )
      end

      # An identity that is already reserved is never executed again. A changed
      # input under the same key was already refused by the store, so anything
      # that reaches here is an identical retry of a run that exists.
      #
      # Reporting the recorded run instead of refusing it is the reconnect path
      # (FR-05); until that exists, the retry fails closed rather than running
      # the turn twice.
      def refuse_duplicate(record)
        raise StreamError, "run #{record.run_id} on thread #{record.thread_id} is already #{record.status}; " \
                           'a reserved run is never executed twice under the same identity'
      end

      def execute(record, to)
        @mapper = build_mapper(record)
        @emitter = Emitter.new(
          writer: SSEWriter.new(to, logger: @logger), mapper: @mapper,
          store: @store, record: record, clock: @clock, logger: @logger
        )
        @emitter.start(run_started_event(record))
        drive
        @record = finish
      rescue RubyLLM::CancelledError
        @record = @emitter.cancel
      rescue StandardError => e
        @record = @emitter.fail(e)
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
        @chat.complete { |chunk| project { @mapper.chunk(chunk) } }
      end

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
        Protocol::RunStartedEvent.new(
          thread_id: record.thread_id, run_id: record.run_id,
          parent_run_id: @input.parent_run_id, input: @input.to_h
        )
      end

      def validate!
        unless @chat.respond_to?(:complete)
          raise ConfigurationError, 'chat must be a RubyLLM::Chat or act like one (it does not respond to #complete)'
        end
        raise ConfigurationError, 'input must be a RubyLLM::AgUI::Input' unless @input.is_a?(Input)

        validate_scope!
      end

      def validate_scope!
        return if @scope.is_a?(String) && !@scope.empty?

        raise ConfigurationError, 'scope must be a non-empty String built from authenticated identity'
      end
    end
  end
end
