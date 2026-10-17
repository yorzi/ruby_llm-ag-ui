# frozen_string_literal: true

module RubyLLM
  module AgUI
    # The few AG-UI 1.0 wire shapes the community Ruby SDK does not yet model.
    #
    # The protocol SDK owns event models and wire encoding, and this gem reuses
    # them for everything else. Two 1.0 shapes are missing from
    # `ag-ui-protocol` 0.2.0:
    #
    # 1. `RunFinishedCancelledOutcome` — 0.2.0 has success and interrupt
    #    outcomes only. A cancellation reported as success is exactly the bug
    #    this gem exists to prevent, so the gem emits a schema-valid cancelled
    #    outcome and offers the model upstream.
    # 2. `RUN_STARTED.protocolVersion` — 1.0 lets a producer declare the
    #    version it speaks so a consumer can see a downgrade. 0.2.0's
    #    RunStartedEvent has no such field.
    #
    # Both classes subclass the SDK's own models, so the SDK encoder serializes
    # them unchanged. They define no top-level `AgUi` constant.
    module Protocol
      # The AG-UI protocol version this producer speaks.
      PROTOCOL_VERSION = '1.0'

      # The pinned upstream commit of docs/spec/1.0/schema.json.
      SCHEMA_COMMIT = '89cedd3fd549feeee41e50e1d7c6d373e549241a'

      # RunFinishedOutcome with the 1.0 "cancelled" discriminator.
      #
      # A cancelled run was stopped before it completed and did not fail. It
      # carries no interrupts, so the next run on the thread is an ordinary new
      # run rather than a resume.
      class CancelledOutcome < ::AgUiProtocol::Core::Types::Model
        # The discriminator value the 1.0 schema requires.
        TYPE = 'cancelled'

        attr_reader :type

        def initialize(type: nil)
          raise ArgumentError, "CancelledOutcome.type must be #{TYPE.inspect}" if !type.nil? && type != TYPE

          super()
          @type = TYPE
        end

        def to_h
          { type: @type }
        end
      end

      # RunStartedEvent that declares the producer's protocol version.
      class RunStartedEvent < ::AgUiProtocol::Core::Events::RunStartedEvent
        attr_reader :protocol_version

        def initialize(protocol_version: PROTOCOL_VERSION, **rest)
          @protocol_version = protocol_version
          super(**rest)
        end

        def to_h
          super.merge(protocol_version: @protocol_version)
        end
      end

      # RunFinishedEvent that accepts the cancelled outcome.
      #
      # The SDK's own RunFinishedEvent validates its +outcome+ against the two
      # outcomes 0.2.0 models, so it cannot carry a cancelled one. This class
      # has the same shape and the same RUN_FINISHED type; it accepts any
      # outcome object that serializes to a schema-valid RunFinishedOutcome,
      # including the SDK's success and interrupt outcomes.
      class RunFinishedEvent < ::AgUiProtocol::Core::Events::BaseEvent
        attr_reader :thread_id, :run_id, :result, :outcome, :usage

        # Mirrors the SDK's own RunFinishedEvent signature.
        def initialize(thread_id:, run_id:, result: nil, outcome: nil, usage: nil, timestamp: nil, raw_event: nil) # rubocop:disable Metrics/ParameterLists
          if !result.nil? && !outcome.nil?
            raise ArgumentError, 'result and outcome are mutually exclusive; provide one or the other, not both'
          end

          super(type: ::AgUiProtocol::Core::Events::EventType::RUN_FINISHED, timestamp: timestamp, raw_event: raw_event)
          @thread_id = thread_id
          @run_id = run_id
          @result = result
          @outcome = outcome
          @usage = usage
        end

        def to_h
          super.merge(thread_id: @thread_id, run_id: @run_id, result: @result, outcome: @outcome, usage: @usage)
        end
      end
    end
  end
end
