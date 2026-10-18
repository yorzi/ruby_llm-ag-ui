# frozen_string_literal: true

module RubyLLM
  module AgUI
    # The authoritative server-side progress of one reserved run.
    #
    # The record is immutable: every transition returns a new record that the
    # store persists. That keeps a run's identity, status and progress honest
    # across processes, and it is what makes "a cancelled run is never reported
    # as success" checkable rather than a comment: once a record reaches a
    # terminal status, no transition can move it to a different one.
    #
    # A record is host bookkeeping, not business truth. The host still owns the
    # conversation, the messages and whatever the tool calls actually did.
    class RunRecord
      # The statuses a run moves through: identity is claimed (RESERVED), the run
      # streams (STARTED), and it ends in exactly one of the terminal statuses.
      RESERVED = :reserved
      STARTED = :started
      # The run ended normally.
      SUCCEEDED = :succeeded
      # The run paused for human input.
      INTERRUPTED = :interrupted
      # The run was stopped before it completed and did not fail.
      CANCELLED = :cancelled
      # The run failed.
      FAILED = :failed

      STATUSES = [RESERVED, STARTED, SUCCEEDED, INTERRUPTED, CANCELLED, FAILED].freeze

      # The statuses a run can end in. A run has exactly one.
      TERMINAL_STATUSES = [SUCCEEDED, INTERRUPTED, CANCELLED, FAILED].freeze

      # The host's tenant/actor/thread scope. Part of every reservation key.
      attr_reader :scope

      # The AG-UI conversation this run belongs to.
      attr_reader :thread_id

      # Identifies this run. Unique within (scope, thread_id).
      attr_reader :run_id

      # The digest of the input this run was reserved for. A retry that sends
      # the same input attaches to this record instead of running twice; a
      # different input under the same key is a conflict.
      attr_reader :digest

      # The run's current status.
      attr_reader :status

      # The highest event sequence number handed out for this run. Snapshots on
      # reconnect are ordered by it rather than by wall-clock time.
      attr_reader :sequence

      # The host-owned run state kept for a reconnect snapshot, or nil.
      attr_reader :snapshot

      # The sanitized failure a reconnect reports for a run that failed, as
      # `{"message" =>, "code" =>}`, or nil. Never the exception itself: a
      # reconnect must not re-leak what the original RUN_ERROR withheld.
      attr_reader :failure

      # The interrupts raised by this run, oldest first.
      attr_reader :interrupts

      attr_reader :created_at, :updated_at

      # rubocop:disable-next Metrics/ParameterLists -- one keyword per field the record owns
      def initialize(scope:, thread_id:, run_id:, digest:, created_at:, status: RESERVED, sequence: 0,
                     snapshot: nil, interrupts: [], failure: nil, updated_at: nil)
        @scope = scope
        @thread_id = thread_id
        @run_id = run_id
        @digest = digest
        @status = assert_status!(status)
        @sequence = sequence
        @snapshot = snapshot
        @interrupts = interrupts.freeze
        @failure = failure
        @created_at = created_at
        @updated_at = updated_at || created_at
        freeze
      end

      # One predicate per status, so callers read `record.interrupted?` rather
      # than comparing symbols.
      STATUSES.each do |status|
        define_method(:"#{status}?") { self.status == status }
      end

      # Whether the run has ended.
      def terminal?
        TERMINAL_STATUSES.include?(status)
      end

      # Whether the run is waiting on a human. Reported as an interrupt outcome;
      # never reported as success.
      def awaiting_approval?
        interrupted? && interrupts.any?(&:pending?)
      end

      # The interrupts that still wait for an answer.
      def pending_interrupts
        interrupts.select(&:pending?)
      end

      # The interrupt with +id+, or nil.
      def interrupt(id)
        interrupts.find { |interrupt| interrupt.id == id }
      end

      # Moves a reserved run to :started, remembering the host-owned state a
      # reconnect serves. Idempotent for an already-started run.
      def start(now:, snapshot: nil)
        return self if started?

        transition_to(STARTED, now: now, snapshot: snapshot)
      end

      # Hands out the next event sequence number.
      def advance(now:)
        with(now: now, sequence: sequence + 1)
      end

      # Closes the run with +status+: :succeeded, :interrupted, :cancelled or
      # :failed, and, for a failure, the sanitized error a reconnect reports.
      # Re-applying the same terminal status is an idempotent no-op — so the
      # first failure wins rather than being replaced by a second, possibly
      # different, explanation — and any other terminal status is a protocol
      # violation, because a run has exactly one outcome.
      def finish(status, now:, failure: nil)
        raise ConfigurationError, "cannot finish a run as #{status.inspect}" unless TERMINAL_STATUSES.include?(status)
        return self if terminal? && self.status == status
        raise StreamError, "run #{run_id} already ended as #{self.status}, not #{status}" if terminal?

        transition_to(status, now: now, failure: failure)
      end

      # Closes the run as interrupted and records the interrupts it raised.
      def interrupted(interrupts, now:)
        raise ConfigurationError, 'an interrupted run needs at least one interrupt' if interrupts.empty?

        pending = interrupts.reject(&:decided?)
        raise ConfigurationError, 'an interrupted run needs at least one unresolved interrupt' if pending.empty?

        transition_to(INTERRUPTED, now: now, interrupts: interrupts)
      end

      # Replaces the interrupt with the same id, keeping its position.
      #
      # This is the one transition that also applies to a terminal record: an
      # interrupted run is closed, and answering its interrupt records the
      # decision on that closed record.
      def replace_interrupt(decided, now:)
        raise ConfigurationError, "no interrupt #{decided.id} on run #{run_id}" unless interrupt(decided.id)

        replaced = interrupts.map { |existing| existing.id == decided.id ? decided : existing }
        with(now: now, interrupts: replaced)
      end

      def to_h
        {
          'scope' => scope.to_s,
          'threadId' => thread_id,
          'runId' => run_id,
          'digest' => digest,
          'status' => status.to_s,
          'sequence' => sequence,
          'snapshot' => snapshot,
          'failure' => failure,
          'interrupts' => interrupts.map(&:to_h),
          'createdAt' => iso8601(created_at),
          'updatedAt' => iso8601(updated_at)
        }
      end

      private

      # rubocop:disable-next Metrics/ParameterLists -- one keyword per field, each defaulted to the record's own
      def with(now:, status: self.status, sequence: self.sequence, snapshot: self.snapshot,
               interrupts: self.interrupts, failure: self.failure)
        self.class.new(
          scope: scope, thread_id: thread_id, run_id: run_id, digest: digest, status: status,
          sequence: sequence, snapshot: snapshot, interrupts: interrupts, failure: failure,
          created_at: created_at, updated_at: now
        )
      end

      def transition_to(status, now:, **attributes)
        raise StreamError, "run #{run_id} already ended as #{self.status}" if terminal?

        with(now: now, status: status, **attributes)
      end

      def iso8601(time)
        time&.utc&.iso8601
      end

      def assert_status!(value)
        return value if STATUSES.include?(value)

        raise ConfigurationError, "status must be one of #{STATUSES.join(', ')}"
      end
    end
  end
end
