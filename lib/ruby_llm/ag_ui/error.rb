# frozen_string_literal: true

module RubyLLM
  module AgUI
    # Base class for every error this gem raises. Rescue it to catch any
    # AG-UI mapping failure without catching unrelated RubyLLM or host errors.
    class Error < StandardError; end

    # Raised when an inbound request cannot be accepted. The message is always
    # safe to send to a client: it never contains raw request bytes.
    class InputError < Error
      # The HTTP status the host should use for this rejection, when it can.
      def http_status
        400
      end
    end

    # Raised when inbound JSON is not valid JSON, or not an object.
    class MalformedInputError < InputError; end

    # Raised when inbound JSON exceeds the configured size or member bounds.
    class InputTooLargeError < InputError
      def http_status
        413
      end
    end

    # Raised when inbound JSON is well formed but violates the AG-UI 1.0
    # RunAgentInput schema.
    class InvalidInputError < InputError; end

    # Raised when the same (scope, threadId, runId) is reserved twice with
    # different input. A duplicate with an identical input attaches instead.
    class RunConflictError < InputError
      def http_status
        409
      end
    end

    # An observed run was changed by another writer. Reload before deciding
    # whether an update is still valid; never overwrite the newer outcome.
    class StaleRecordError < RunConflictError; end

    # Raised when run identity is required but missing.
    class InvalidRunIdentityError < InvalidInputError; end

    # Raised when a resume entry does not match a live interrupt of the most
    # recent interrupted run on the thread, or was already redeemed. Fails
    # closed: nothing is executed and no decision is recorded.
    class ResumeRejectedError < InputError
      def http_status
        409
      end
    end

    # Raised when the host did not supply something a run needs (a chat, a run
    # store, an actor scope) or supplied something malformed.
    class ConfigurationError < Error; end

    # Raised when the pinned protocol version is not the one this gem speaks.
    class UnsupportedProtocolVersionError < InputError; end

    # Raised when run or stream ordering cannot be honored.
    class StreamError < Error; end

    # The response transport is closed. A running producer detaches its writer
    # and continues to persist the real outcome while its worker remains alive.
    class TransportError < StreamError; end

    # A store write failed without a reliable acknowledgement. The persisted
    # outcome may be unknown; inspect storage before attempting recovery.
    class PersistenceError < Error; end

    # Raised when RubyLLM paused the run for something the pinned AG-UI shape
    # cannot express as an interrupt this producer may answer, such as an MCP
    # input request or a long-running MCP task. Reported as a sanitized
    # RUN_ERROR rather than a success or a bare interrupt.
    class UnsupportedRunStateError < Error; end
  end
end
