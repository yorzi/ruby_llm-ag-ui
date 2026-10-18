# frozen_string_literal: true

module RubyLLM
  module AgUI
    # One approval request attached to a reserved run, and the answer to it.
    #
    # A RubyLLM `requires_approval` pause becomes one interrupt per pending tool
    # call. The interrupt is the only thing that ties a client resume entry to a
    # tool call, and it is deliberately narrow:
    #
    # * it names the exact `toolCallId` and the digest of the arguments RubyLLM
    #   asked to run, so a resume that tries to change the arguments cannot pass
    #   as the same request;
    # * it carries a host-owned expiry, so an old approval does not stay valid
    #   forever;
    # * it records exactly one decision, so a replayed resume entry gets the
    #   stored decision back instead of running the tool a second time.
    #
    # An interrupt is not a permission grant. The host re-authorizes the actor
    # before the tool runs, whatever this record says.
    class Interrupt
      # No decision yet.
      PENDING = :pending
      # The actor approved the tool call.
      APPROVED = :approved
      # The actor declined the tool call.
      DENIED = :denied
      # The actor abandoned the interrupt.
      CANCELLED = :cancelled

      STATUSES = [PENDING, APPROVED, DENIED, CANCELLED].freeze

      # The statuses that count as an answer.
      DECISIONS = [APPROVED, DENIED, CANCELLED].freeze

      # The protocol's reason for a tool approval.
      REASON_TOOL_CALL = 'tool_call_confirmation'

      # An id unique among the interrupts of one thread. A resume entry answers
      # an interrupt by this id, so it must be unguessable enough that a client
      # cannot answer someone else's approval.
      attr_reader :id

      # The RubyLLM tool call this interrupt concerns.
      attr_reader :tool_call_id

      # Why the run stopped. An open protocol string.
      attr_reader :reason

      # A human-readable prompt for whoever answers.
      attr_reader :message

      # The SHA-256 digest of the arguments RubyLLM asked to run. Compared
      # before execution so changed arguments cannot reuse an approval.
      attr_reader :arguments_digest

      # When the interrupt stops being answerable.
      attr_reader :expires_at

      # :pending, :approved, :denied or :cancelled.
      attr_reader :status

      # When the decision was recorded, or nil while pending.
      attr_reader :decided_at

      # When the interrupt was created.
      attr_reader :created_at

      # rubocop:disable Metrics/ParameterLists -- one keyword per field the value object owns
      def initialize(id:, tool_call_id:, arguments_digest:, expires_at:, reason: REASON_TOOL_CALL,
                     message: nil, status: PENDING, decided_at: nil, created_at: nil)
        @id = id
        @tool_call_id = tool_call_id
        @arguments_digest = arguments_digest
        @expires_at = expires_at
        @reason = reason
        @message = message
        @status = assert_status!(status)
        @decided_at = decided_at
        @created_at = created_at
        freeze
      end

      # Builds an interrupt with an unguessable id.
      def self.create(tool_call_id:, arguments_digest:, expires_at:, reason: REASON_TOOL_CALL, message: nil,
                      created_at: nil)
        new(
          id: SecureRandom.uuid, tool_call_id: tool_call_id, arguments_digest: arguments_digest,
          expires_at: expires_at, reason: reason, message: message, created_at: created_at
        )
      end
      # rubocop:enable Metrics/ParameterLists

      # Whether the interrupt still waits for an answer.
      def pending?
        status == PENDING
      end

      # Whether a decision has been recorded.
      def decided?
        DECISIONS.include?(status)
      end

      # Whether the actor approved the call.
      def approved?
        status == APPROVED
      end

      # Whether the actor declined the call.
      def denied?
        status == DENIED
      end

      # Whether the actor abandoned the interrupt.
      def cancelled?
        status == CANCELLED
      end

      # Whether the host-owned expiry has passed at +now+.
      def expired?(now)
        !expires_at.nil? && now >= expires_at
      end

      # Whether the interrupt can still be answered at +now+.
      def answerable?(now)
        pending? && !expired?(now)
      end

      # Returns a copy carrying +decision+. Refuses to overwrite an existing
      # decision: a second answer is a replay or a conflict, never a new grant.
      def decide(decision, now:)
        raise ConfigurationError, "decision must be one of #{DECISIONS.join(', ')}" unless DECISIONS.include?(decision)
        raise StreamError, "interrupt #{id} was already #{status}" if decided?

        self.class.new(
          id: id, tool_call_id: tool_call_id, arguments_digest: arguments_digest, expires_at: expires_at,
          reason: reason, message: message, status: decision, decided_at: now, created_at: created_at
        )
      end

      # The protocol's Interrupt shape, ready for a RUN_FINISHED interrupt
      # outcome. Only the fields the pinned schema defines are set.
      def to_protocol
        ::AgUiProtocol::Core::Types::Interrupt.new(
          id: id,
          reason: reason,
          message: message,
          tool_call_id: tool_call_id,
          expires_at: expires_at&.utc&.iso8601
        )
      end

      # The interrupt as plain data, with camelCase keys. The arguments digest
      # and the caller-supplied ids stay out of it: they are host bookkeeping.
      def to_h
        {
          'id' => id,
          'toolCallId' => tool_call_id,
          'reason' => reason,
          'message' => message,
          'expiresAt' => iso8601(expires_at),
          'status' => status.to_s,
          'decidedAt' => iso8601(decided_at)
        }
      end

      # The interrupt in the form a durable store keeps, which #to_h is not: a
      # store that dropped the arguments digest could not re-verify that a
      # resume answers the call it approved, and one that dropped the creation
      # time could not order two interrupts on a thread.
      def to_storage
        to_h.merge(
          'argumentsDigest' => arguments_digest,
          'createdAt' => iso8601(created_at)
        )
      end

      # Rebuilds an interrupt stored by #to_storage.
      def self.from_storage(hash)
        new(
          id: hash.fetch('id'), tool_call_id: hash.fetch('toolCallId'),
          arguments_digest: hash.fetch('argumentsDigest'), reason: hash.fetch('reason'),
          message: hash['message'], expires_at: parse_time(hash['expiresAt']),
          status: hash.fetch('status').to_sym, decided_at: parse_time(hash['decidedAt']),
          created_at: parse_time(hash['createdAt'])
        )
      end

      # The time +value+ names, or nil. Storage writes ISO 8601 strings.
      def self.parse_time(value)
        value.nil? ? nil : Time.iso8601(value)
      end

      private

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
