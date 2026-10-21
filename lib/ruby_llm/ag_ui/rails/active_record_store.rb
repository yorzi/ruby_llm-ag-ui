# frozen_string_literal: true

module RubyLLM
  module AgUI
    module Rails
      # Defining the row class loads ActiveRecord::Base. Defer it to first use,
      # so requiring the gem during a Rails boot does not load Active Record
      # before the host's configuration.
      autoload :Record, File.expand_path('record', __dir__)

      # The durable run store: run identity in a table instead of a process.
      #
      # The in-process store is correct for one process only. A host that runs
      # more than one Puma worker, or that restarts, needs the reservation, the
      # interrupts and the terminal status to outlive the worker that produced
      # them, which is what this store is for.
      #
      # Ordering is by row id, so "the latest run on the thread" means the run
      # reserved last, not the run whose clock reading is largest. Two requests
      # that arrive in the same millisecond still have an order.
      #
      #     RubyLLM::AgUI.configure { |config| config.run_store = ActiveRecordStore.new }
      class ActiveRecordStore < Store::Base
        # Claims (scope, thread_id, run_id) for +digest+.
        #
        # The unique index on the identity is the real guard: two workers that
        # insert at the same time cannot both win, and the loser attaches to the
        # row the winner wrote instead of executing the turn a second time.
        def reserve(scope:, thread_id:, run_id:, digest:)
          scope_key(scope)
          record = RunRecord.new(
            scope: scope, thread_id: thread_id, run_id: run_id, digest: digest, created_at: now
          )
          Record.from_run_record(record).save!
          Reservation.new(record: record, status: Reservation::CREATED)
        rescue ::ActiveRecord::RecordNotUnique
          attach(row_for(scope, thread_id, run_id), digest)
        end

        def find(scope:, thread_id:, run_id:)
          row_for(scope, thread_id, run_id)&.as_run_record
        end

        def latest_run(scope:, thread_id:)
          thread_rows(scope, thread_id).last&.as_run_record
        end

        def latest_interrupted(scope:, thread_id:)
          interrupted = RunRecord::INTERRUPTED.to_s
          thread_rows(scope, thread_id).reverse.find { |row| row.status == interrupted }&.as_run_record
        end

        def save(record)
          scope_key(record.scope)
          row = row_for(record.scope, record.thread_id, record.run_id)
          updated = next_record(row&.as_run_record, record)
          row.write_run_record(updated)
        end

        def find_interrupt(scope:, thread_id:, interrupt_id:)
          raise InvalidInputError, 'interrupt_id is required.' if blank?(interrupt_id)

          row_for_interrupt(scope, thread_id, interrupt_id)&.as_run_record&.interrupt(interrupt_id)
        end

        # Records +decision+ with a conditional update. Competing writers reload
        # and revalidate, so only one can redeem the approval.
        def redeem_interrupt(scope:, thread_id:, interrupt_id:, decision:, now:)
          unless Interrupt::DECISIONS.include?(decision)
            raise ConfigurationError, "decision must be one of #{Interrupt::DECISIONS.join(', ')}"
          end

          retry_stale do
            row = row_for_interrupt(scope, thread_id, interrupt_id)
            raise ResumeRejectedError, "no interrupt #{interrupt_id}" if row.nil?

            redeem(row.as_run_record, interrupt_id, decision, now)
          end
        end

        private

        def retry_stale
          attempts = 0
          begin
            yield
          rescue StaleRecordError
            attempts += 1
            retry if attempts < 3
            raise
          end
        end

        # A retry of the same identity attaches; a different input under the
        # same key is a conflict, because one run id may not mean two requests.
        def attach(row, digest)
          raise RunConflictError, conflict_message(row.as_run_record) if row.digest != digest

          Reservation.new(record: row.reload.as_run_record, status: Reservation::ATTACHED)
        end

        def redeem(record, interrupt_id, decision, now)
          interrupt = record.interrupt(interrupt_id)
          return replay(interrupt, decision) if interrupt.decided?
          raise ResumeRejectedError, "interrupt #{interrupt_id} expired" if interrupt.expired?(now)

          answered = interrupt.decide(decision, now: now)
          save(record.replace_interrupt(answered, now: now))
          Redemption.new(interrupt: answered, replayed: false)
        end

        def row_for(scope, thread_id, run_id)
          return nil if blank?(scope) || blank?(thread_id) || blank?(run_id)

          Record.find_by(scope: scope, thread_id: thread_id, run_id: run_id)
        end

        def thread_rows(scope, thread_id)
          Record.where(scope: scope, thread_id: thread_id).order(:id).to_a
        end

        # An interrupt id is unique among a thread's runs, so the thread is
        # searched newest first and the first row that knows the id wins. A
        # thread holds few runs, and the alternative is a JSON query that would
        # bind this store to one database.
        def row_for_interrupt(scope, thread_id, interrupt_id)
          thread_rows(scope, thread_id).reverse.find { |row| row.as_run_record.interrupt(interrupt_id) }
        end
      end
    end
  end
end
