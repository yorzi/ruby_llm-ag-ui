# frozen_string_literal: true

module RubyLLM
  module AgUI
    # The result of redeeming an interrupt.
    #
    # A caller cannot tell a fresh decision from a replay by the interrupt
    # alone: both come back approved. The distinction is exactly what decides
    # whether the tool may run, so the store returns it explicitly. Only the
    # call that recorded the decision may execute the tool; a replay reports the
    # answer already given and must not run anything again.
    class Redemption
      # The stored interrupt, with its decision.
      attr_reader :interrupt

      def initialize(interrupt:, replayed:)
        @interrupt = interrupt
        @replayed = replayed
        freeze
      end

      # Whether this call recorded the decision.
      def recorded?
        !@replayed
      end

      # Whether the decision was already recorded by an earlier call.
      def replayed?
        @replayed
      end

      # The interrupt's status: :approved, :denied or :cancelled.
      def status
        interrupt.status
      end

      # Whether the stored decision is an approval.
      def approved?
        interrupt.approved?
      end

      # Whether the stored decision is a refusal.
      def denied?
        interrupt.denied?
      end

      # Whether the stored decision abandons the interrupt.
      def cancelled?
        interrupt.cancelled?
      end

      # The tool call the decision concerns.
      def tool_call_id
        interrupt.tool_call_id
      end

      def to_h
        { 'interruptId' => interrupt.id, 'status' => status.to_s, 'replayed' => replayed? }
      end
    end
  end
end
