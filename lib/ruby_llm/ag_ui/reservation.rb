# frozen_string_literal: true

module RubyLLM
  module AgUI
    # The answer to a run reservation: the record that owns the identity, and
    # how the reservation was obtained.
    #
    # A retried request whose input digest matches an existing reservation gets
    # ATTACHED, so the host streams or reports the run already in progress
    # instead of executing it a second time.
    class Reservation
      # The identity was free and is now claimed by this call.
      CREATED = :created
      # The identity was already claimed by an identical request.
      ATTACHED = :attached

      # The record that owns the run identity.
      attr_reader :record

      # :created or :attached.
      attr_reader :status

      def initialize(record:, status:)
        @record = record
        @status = status
        freeze
      end

      # Whether this call claimed the identity.
      def created?
        status == CREATED
      end

      # Whether the identity was already claimed by an identical request.
      def attached?
        status == ATTACHED
      end

      def thread_id
        record.thread_id
      end

      def run_id
        record.run_id
      end

      def digest
        record.digest
      end

      def to_h
        { 'status' => status.to_s, 'threadId' => thread_id, 'runId' => run_id, 'digest' => digest }
      end
    end
  end
end
