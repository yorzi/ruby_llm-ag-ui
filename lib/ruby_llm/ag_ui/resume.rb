# frozen_string_literal: true

module RubyLLM
  module AgUI
    # The answers a run's input gives to a previous run's interrupts (FR-06).
    #
    # A resume is a request, never a permission grant. Before anything is
    # written, every entry is checked against the live state: it must name an
    # interrupt of the *most recent* interrupted run on the same thread, the
    # tool call it concerns must still be pending on the host's chat, and that
    # call's arguments must still digest to what the interrupt recorded, so a
    # resume cannot change what it approves. The decision is then recorded once;
    # a repeated resume is refused rather than executed again, because the tool
    # may already have run.
    #
    # An approval answers an interrupt. The host still re-authorizes the actor
    # before the tool executes.
    class Resume
      # One entry's effect: the interrupt it answers and the decision to record.
      Decision = Struct.new(:interrupt, :decision, keyword_init: true)

      def initialize(input:, store:, scope:, chat:)
        @input = input
        @store = store
        @scope = scope
        @chat = chat
        @plan = []
      end

      # Whether the input answers anything at all.
      def needed?
        @input.resume?
      end

      # Checks a new resume and builds its plan before the run opens a stream.
      # An existing identity is left to reservation and reconnect: an exact
      # retry reports its recorded outcome, never redeems the decision twice.
      def plan(now:)
        existing = @store.find(scope: @scope, thread_id: @input.thread_id, run_id: @input.run_id)
        return self if existing

        source = interrupted_run
        @plan = @input.resume.map { |entry| plan_entry(source, entry, now) }
        self
      end

      # Records each planned decision once and tells the chat about it, so the
      # next completion runs an approved tool or refuses a denied one.
      def apply(now:)
        @plan.each { |planned| redeem(planned, now: now) }
        self
      end

      private

      # Only the most recent interrupted run on the thread is resumable.
      # Anything older is stale, and answering it would apply a decision to a
      # conversation that has already moved on.
      def interrupted_run
        record = @store.latest_interrupted(scope: @scope, thread_id: @input.thread_id)
        raise ResumeRejectedError, "thread #{@input.thread_id} has no interrupted run to resume" if record.nil?

        record
      end

      def plan_entry(source, entry, now)
        interrupt = source.interrupt(entry.interrupt_id)
        raise ResumeRejectedError, "interrupt #{entry.interrupt_id} is not the latest run's" if interrupt.nil?
        raise ResumeRejectedError, "interrupt #{interrupt.id} has already been answered" unless interrupt.pending?
        raise ResumeRejectedError, "interrupt #{interrupt.id} has expired" if interrupt.expired?(now)

        ensure_unchanged!(interrupt)
        Decision.new(interrupt: interrupt, decision: decision_for(entry))
      end

      # The call an interrupt approves must still be pending on the host's chat
      # with the same arguments. A resume answers the question that was asked; it
      # cannot change it.
      def ensure_unchanged!(interrupt)
        tool_call = pending_approval(interrupt.tool_call_id)
        raise ResumeRejectedError, "tool call #{interrupt.tool_call_id} is not pending on this chat" unless tool_call

        return if Canonical.digest(tool_call.arguments) == interrupt.arguments_digest

        raise ResumeRejectedError, "arguments for tool call #{interrupt.tool_call_id} changed since the interrupt"
      end

      # The store's redemption is atomic: the first answer record wins, and a
      # repeat comes back as a replay that must not execute anything.
      def redeem(planned, now:)
        redemption = persist_decision(planned, now: now)
        raise ResumeRejectedError, "interrupt #{planned.interrupt.id} was already answered" if redemption.replayed?

        redemption.approved? ? @chat.approve(redemption.tool_call_id) : @chat.deny(redemption.tool_call_id)
      end

      def persist_decision(planned, now:)
        Persistence.write do
          @store.redeem_interrupt(scope: @scope, thread_id: @input.thread_id,
                                  interrupt_id: planned.interrupt.id, decision: planned.decision, now: now)
        end
      end

      # The protocol's resume vocabulary is resolved or cancelled; the interrupt
      # records the truthful decision, and a cancelled answer denies the call
      # rather than approving it.
      def decision_for(entry)
        entry.resolved? ? Interrupt::APPROVED : Interrupt::CANCELLED
      end

      def pending_approval(tool_call_id)
        @chat.pending_approvals.find { |tool_call| tool_call.id == tool_call_id }
      end
    end
  end
end
