# frozen_string_literal: true

module RubyLLM
  module AgUI
    # Writes one run's events and keeps its durable record in step.
    #
    # The mapper decides which events a RubyLLM signal becomes; the emitter is
    # what makes them durable and ordered. Every event advances the run record's
    # sequence, so a reconnect can order snapshots by it instead of by wall
    # clock, and a terminal outcome is persisted *before* it is written: if the
    # transport dies after the outcome is decided, the run still cannot be
    # executed a second time.
    #
    # The emitter decides nothing about the outcome and executes nothing. What it
    # owns is the one ordering rule a caller should never have to remember: a
    # run's open text, tool calls and step are closed before the terminal event.
    class Emitter
      # The run record, including the sequence numbers written so far.
      attr_reader :record

      # rubocop:disable-next Metrics/ParameterLists -- one keyword per collaborator the caller injects
      def initialize(writer:, mapper:, store:, record:, clock:, logger: nil)
        @writer = writer
        @mapper = mapper
        @store = store
        @record = record
        @clock = clock
        @logger = logger
      end

      # Moves the run to started, then opens it on the wire with +event+.
      def start(event)
        @record = persist(@record.start(now: now))
        write(event)
        @record
      end

      # Writes +events+ (one event or an array) and advances the run's sequence
      # by one per event.
      def write(events)
        Array(events).each do |event|
          @writer.write(event)
          @record = @record.advance(now: now)
        end
      end

      # Closes the run as succeeded.
      def succeed
        @record = persist(@record.finish(RunRecord::SUCCEEDED, now: now))
        close(run_finished(::AgUiProtocol::Core::Events::RunFinishedSuccessOutcome.new))
        @record
      end

      # Closes a run that was stopped before it completed. Never reported as a
      # success: the outcome carries the protocol's own "cancelled"
      # discriminator, which 0.2.0 cannot express.
      def cancel
        @record = persist(@record.finish(RunRecord::CANCELLED, now: now))
        close(run_finished(Protocol::CancelledOutcome.new))
        @record
      end

      # Closes the run as paused, recording +interrupts+ so a later resume can
      # answer them by id. At least one must be unresolved, which RunRecord
      # enforces.
      def interrupt(interrupts)
        outcome = ::AgUiProtocol::Core::Events::RunFinishedInterruptOutcome.new(
          interrupts: interrupts.map(&:to_protocol)
        )
        @record = persist(@record.interrupted(interrupts, now: now))
        close(run_finished(outcome))
        @record
      end

      # Closes the run as failed with a sanitized RUN_ERROR.
      #
      # The record is persisted first, so a run that failed is not retried
      # because reporting the failure failed too. The exception's own message is
      # never sent: it may carry prompts, keys or paths.
      def fail(error)
        message, code = ErrorSanitizer.sanitize(error)
        @logger&.warn("[ruby_llm_ag_ui] run #{@record.run_id} failed: #{error.class}")
        @record = persist(@record.finish(RunRecord::FAILED, now: now))
        close(::AgUiProtocol::Core::Events::RunErrorEvent.new(message: message, code: code))
        @record
      end

      private

      # Closes whatever content is still open, then writes the terminal event.
      def close(terminal_event)
        write(@mapper.close)
        write(terminal_event)
      end

      def run_finished(outcome)
        Protocol::RunFinishedEvent.new(thread_id: @record.thread_id, run_id: @record.run_id, outcome: outcome)
      end

      def persist(record)
        @store.save(record)
      end

      def now
        @clock.call
      end
    end
  end
end
