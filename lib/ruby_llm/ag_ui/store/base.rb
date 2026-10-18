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
      #
      # The private helpers below are not part of the interface: they are the
      # parts of the contract two stores would otherwise implement twice (the
      # scope key, the clock, the replay rule). A store that duck-types the
      # public methods has to satisfy them itself.
      class Base
        # Raised when a host passes a scope that cannot identify a tenant.
        SCOPE_MESSAGE = 'scope must be a non-empty String built from authenticated identity'

        def initialize(clock: nil)
          @clock = clock || RubyLLM::AgUI.config.clock
        end

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

        private

        # The host's scope must be a canonical string. An arbitrary object would
        # make two requests from the same tenant hash differently, so a retry
        # would not attach and the run would execute twice.
        def scope_key(scope)
          raise ConfigurationError, SCOPE_MESSAGE unless scope.is_a?(String) && !scope.empty?

          scope
        end

        def now
          @clock.call
        end

        def blank?(value)
          value.nil? || (value.respond_to?(:empty?) && value.empty?)
        end

        # A repeat of the stored decision is a replay: the caller is told the
        # answer already given and must not execute the tool again. A second
        # answer that disagrees rescinds nothing and is refused.
        def replay(interrupt, decision)
          return Redemption.new(interrupt: interrupt, replayed: true) if interrupt.status == decision

          raise ResumeRejectedError, "interrupt #{interrupt.id} was already #{interrupt.status}"
        end

        def conflict_message(record)
          "run #{record.run_id} on thread #{record.thread_id} was already reserved with a different input"
        end
      end
    end
  end
end
