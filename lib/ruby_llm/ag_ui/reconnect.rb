# frozen_string_literal: true

module RubyLLM
  module AgUI
    # What a client that re-sends an input whose run already ended gets (FR-05).
    #
    # A reconnect is not a second execution. The run ended, so the client gets
    # its outcome and the state snapshot the run recorded instead of the deltas
    # it may already have — or may have missed. Replaying deltas would apply text
    # twice and could run a tool twice, so they are never replayed.
    #
    # What cannot be served this way is a run that has not ended: attaching a
    # second stream to a live run needs a relay the gem does not own, and a
    # silent second stream would duplicate the work. Those are refused.
    class Reconnect
      # The failure reported for a run that failed before its sanitized error
      # was recorded — a record from an older release, or one whose write was
      # interrupted.
      UNRECORDED_FAILURE = {
        'message' => 'The run failed before it could finish.', 'code' => 'internal_error'
      }.freeze

      # Whether +record+ can be served to a client that reconnects.
      def self.serves?(record)
        record.terminal?
      end

      def initialize(record:, input:)
        @record = record
        @input = input
      end

      # The events to write, in order: the run opens, declares the state it owns,
      # and reports the outcome already recorded.
      def events
        [open_event, *snapshot_events, terminal_event]
      end

      private

      def open_event
        Protocol.run_started(
          thread_id: @record.thread_id, run_id: @record.run_id,
          parent_run_id: @input.parent_run_id, input: @input.to_h
        )
      end

      def snapshot_events
        return [] if @record.snapshot.nil?

        [Protocol.state_snapshot(@record.snapshot)]
      end

      def terminal_event
        case @record.status
        when RunRecord::SUCCEEDED then finished(Protocol.success_outcome)
        when RunRecord::CANCELLED then finished(Protocol.cancelled_outcome)
        when RunRecord::INTERRUPTED then interrupted_event
        else failure_event
        end
      end

      def finished(outcome)
        Protocol.run_finished(thread_id: @record.thread_id, run_id: @record.run_id, outcome: outcome)
      end

      # An interrupted run whose interrupts have all been answered was continued
      # by a resume run, which owns what happened next. The run therefore has no
      # interrupt to report (the schema requires at least one), and saying so is
      # more honest than reporting answered interrupts as if they still waited.
      def interrupted_event
        return finished(Protocol.interrupt_outcome(@record.pending_interrupts)) if @record.pending_interrupts.any?

        ::AgUiProtocol::Core::Events::RunErrorEvent.new(
          message: 'This run ended interrupted, and every interrupt has been answered.',
          code: 'run_resumed'
        )
      end

      def failure_event
        failure = @record.failure || UNRECORDED_FAILURE
        ::AgUiProtocol::Core::Events::RunErrorEvent.new(message: failure['message'], code: failure['code'])
      end
    end
  end
end
