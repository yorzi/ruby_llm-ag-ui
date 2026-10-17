# frozen_string_literal: true

module RubyLLM
  module AgUI
    module Store
      # An in-process run store.
      #
      # It is correct for a single process and a reasonable default in
      # development and tests. It is not shared between processes, so a host
      # that runs more than one Puma worker, or retries on a different worker,
      # must use a durable store (the optional Rails adapter's ActiveRecord
      # store) instead. Nothing here pretends otherwise.
      #
      # Every public method holds the store's lock for its whole body, so the
      # reservation and the interrupt redemption are atomic: the first caller to
      # answer an interrupt is the only one that records a decision. The private
      # helpers assume the lock is already held and never take it themselves.
      class MemoryStore < Base
        # Raised when a host passes a scope that cannot identify a tenant.
        SCOPE_MESSAGE = 'scope must be a non-empty String built from authenticated identity'

        def initialize(clock: nil)
          super()
          @clock = clock || RubyLLM::AgUI.config.clock
          @records = {}
          @threads = {}
          @lock = Mutex.new
        end

        def reserve(scope:, thread_id:, run_id:, digest:)
          key = key_for(scope, thread_id, run_id)
          @lock.synchronize do
            existing = @records[key]
            next attach(existing, digest) if existing

            record = RunRecord.new(
              scope: scope, thread_id: thread_id, run_id: run_id, digest: digest, created_at: now
            )
            @records[key] = record
            thread = thread_key(scope, thread_id)
            @threads[thread] = (@threads[thread] || []) + [run_id]
            Reservation.new(record: record, status: Reservation::CREATED)
          end
        end

        def find(scope:, thread_id:, run_id:)
          key = key_for(scope, thread_id, run_id)
          @lock.synchronize { @records[key] }
        end

        def latest_run(scope:, thread_id:)
          @lock.synchronize { records_for(scope, thread_id).last }
        end

        def latest_interrupted(scope:, thread_id:)
          @lock.synchronize { records_for(scope, thread_id).reverse.find(&:interrupted?) }
        end

        def save(record)
          key = key_for(record.scope, record.thread_id, record.run_id)
          @lock.synchronize do
            stored = @records[key]
            raise InvalidRunIdentityError, "run #{record.run_id} was never reserved" if stored.nil?
            raise RunConflictError, conflict_message(record) if stored.digest != record.digest

            @records[key] = record
          end
          record
        end

        def find_interrupt(scope:, thread_id:, interrupt_id:)
          raise InvalidInputError, 'interrupt_id is required.' if blank?(interrupt_id)

          @lock.synchronize { record_for_interrupt(scope, thread_id, interrupt_id)&.interrupt(interrupt_id) }
        end

        def redeem_interrupt(scope:, thread_id:, interrupt_id:, decision:, now:)
          unless Interrupt::DECISIONS.include?(decision)
            raise ConfigurationError, "decision must be one of #{Interrupt::DECISIONS.join(', ')}"
          end

          @lock.synchronize { redeem(scope, thread_id, interrupt_id, decision, now) }
        end

        private

        def redeem(scope, thread_id, interrupt_id, decision, now)
          record = record_for_interrupt(scope, thread_id, interrupt_id)
          raise ResumeRejectedError, "no interrupt #{interrupt_id}" if record.nil?

          interrupt = record.interrupt(interrupt_id)
          return replay(interrupt, decision) if interrupt.decided?
          raise ResumeRejectedError, "interrupt #{interrupt_id} expired" if interrupt.expired?(now)

          answered = interrupt.decide(decision, now: now)
          @records[key_for(scope, thread_id, record.run_id)] = record.replace_interrupt(answered, now: now)
          Redemption.new(interrupt: answered, replayed: false)
        end

        # A repeat of the stored decision is a replay: the caller is told the
        # answer already given and must not execute the tool again.
        def replay(interrupt, decision)
          return Redemption.new(interrupt: interrupt, replayed: true) if interrupt.status == decision

          raise ResumeRejectedError, "interrupt #{interrupt.id} was already #{interrupt.status}"
        end

        def record_for_interrupt(scope, thread_id, interrupt_id)
          records_for(scope, thread_id).reverse.find { |record| record.interrupt(interrupt_id) }
        end

        def attach(existing, digest)
          raise RunConflictError, conflict_message(existing) if existing.digest != digest

          Reservation.new(record: existing, status: Reservation::ATTACHED)
        end

        def conflict_message(record)
          "run #{record.run_id} on thread #{record.thread_id} was already reserved with a different input"
        end

        def records_for(scope, thread_id)
          thread = @threads[thread_key(scope, thread_id)] || []
          thread.filter_map { |run_id| @records[key_for(scope, thread_id, run_id)] }
        end

        def key_for(scope, thread_id, run_id)
          [scope_key(scope), thread_id, run_id]
        end

        def thread_key(scope, thread_id)
          [scope_key(scope), thread_id]
        end

        # The host's scope must be a canonical string. An arbitrary object would
        # make two requests from the same tenant hash differently, so a retry
        # would not attach and the run would execute twice.
        def scope_key(scope)
          raise ConfigurationError, SCOPE_MESSAGE unless scope.is_a?(String) && !scope.empty?

          scope
        end

        def blank?(value)
          value.nil? || (value.respond_to?(:empty?) && value.empty?)
        end

        def now
          @clock.call
        end
      end
    end
  end
end
