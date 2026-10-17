# frozen_string_literal: true

module RubyLLM
  module AgUI
    # Run identity and progress storage.
    #
    # The store is where run identity becomes durable: it reserves a run before
    # any provider work happens, so a retried request attaches to the run
    # already in progress instead of executing twice, and it keeps the
    # interrupts that a later resume has to answer.
    #
    # Two stores ship with the gem: Store::MemoryStore, which is the default for
    # a single process, and the optional Rails adapter's ActiveRecord store. A
    # host may implement this interface instead; every method must be safe to
    # call from concurrent threads.
    #
    # `scope` is the host's own tenant/actor boundary. The store treats it as an
    # opaque key, so the host must build it from authenticated identity (for
    # example `"#{tenant.id}:#{actor.id}"`). Two scopes never share state, which
    # is what stops one tenant from attaching to another's run.
    module Store
      # The interface every store implements. Subclass it to get the documented
      # contract in one place, or duck-type it.
      class Base
        # Claims (scope, thread_id, run_id) for +digest+.
        #
        # Returns a Reservation whose record is the run's authoritative state.
        # A second call with the same key and an identical digest returns an
        # ATTACHED reservation; a different digest raises RunConflictError,
        # because the same run id may not mean two different requests.
        def reserve(scope:, thread_id:, run_id:, digest:)
          raise NotImplementedError
        end

        # The record for an exact identity, or nil.
        def find(scope:, thread_id:, run_id:)
          raise NotImplementedError
        end

        # The most recent run on the thread. Used to answer "what is this thread
        # doing right now" without executing anything.
        def latest_run(scope:, thread_id:)
          raise NotImplementedError
        end

        # The most recent run on the thread that ended interrupted, or nil.
        #
        # A resume entry may only answer an interrupt of this run; anything
        # older is stale and must be refused.
        def latest_interrupted(scope:, thread_id:)
          raise NotImplementedError
        end

        # Persists an updated record and returns it.
        def save(record)
          raise NotImplementedError
        end

        # The interrupt with +id+ anywhere on the thread, or nil.
        def find_interrupt(scope:, thread_id:, interrupt_id:)
          raise NotImplementedError
        end

        # Atomically records +decision+ on the interrupt with +interrupt_id+ and
        # returns a Redemption.
        #
        # The first answer wins. A repeated answer with the same decision
        # returns the stored interrupt as a replay, so a replayed resume request
        # cannot run the tool twice; Redemption#recorded? says which call won.
        # An expired interrupt, an unknown id, or a second answer that disagrees
        # with the stored decision raises ResumeRejectedError: nothing is
        # recorded and nothing is executed.
        def redeem_interrupt(scope:, thread_id:, interrupt_id:, decision:, now:)
          raise NotImplementedError
        end
      end
    end
  end
end
