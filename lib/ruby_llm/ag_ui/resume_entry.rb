# frozen_string_literal: true

module RubyLLM
  module AgUI
    # One answer to one interrupt, as the client sends it on the run that
    # continues from an interrupted one.
    #
    # A resume entry is a request, never a permission grant: the run still
    # checks that the interrupt exists, belongs to the most recent interrupted
    # run on this thread, has not been redeemed, and has not expired, and the
    # host still re-authorizes before any tool runs.
    class ResumeEntry
      # The protocol's two statuses.
      RESOLVED = 'resolved'
      CANCELLED = 'cancelled'
      STATUSES = [RESOLVED, CANCELLED].freeze

      # Identifies the interrupt this entry answers.
      attr_reader :interrupt_id

      # "resolved" or "cancelled".
      attr_reader :status

      # The answer the client supplies, for an interrupt that asked for one.
      attr_reader :payload

      def initialize(interrupt_id:, status:, payload: nil)
        @interrupt_id = interrupt_id
        @status = status
        @payload = payload
        freeze
      end

      # Whether the client answered the interrupt.
      def resolved?
        status == RESOLVED
      end

      # Whether the client abandoned the interrupt.
      def cancelled?
        status == CANCELLED
      end

      def to_h
        { 'interruptId' => interrupt_id, 'status' => status, 'payload' => payload }
      end
    end
  end
end
