# frozen_string_literal: true

RSpec.describe RubyLLM::AgUI::Protocol do
  let(:encoder) { AgUiProtocol::EventEncoder.new }
  let(:decoded) { JSON.parse(encoded.sub(/\Adata: /, '')) }

  describe RubyLLM::AgUI::Protocol::CancelledOutcome do
    subject(:outcome) { described_class.new }

    it 'is a schema-valid cancelled outcome' do
      expect(outcome.to_h).to eq(type: 'cancelled')
      expect(outcome.type).to eq('cancelled')
    end

    it 'accepts its own discriminator for round-tripping' do
      expect(described_class.new(type: 'cancelled').type).to eq('cancelled')
    end

    it 'rejects any other discriminator' do
      expect { described_class.new(type: 'success') }.to raise_error(ArgumentError, /must be "cancelled"/)
    end
  end

  describe RubyLLM::AgUI::Protocol::RunStartedEvent do
    subject(:event) { described_class.new(thread_id: 'thread-1', run_id: 'run-1') }

    it 'defaults protocol_version to the pinned 1.0 version' do
      expect(event.protocol_version).to eq('1.0')
    end

    it 'is still an ag-ui-protocol event' do
      expect(event).to be_a(AgUiProtocol::Core::Events::RunStartedEvent)
    end
  end

  describe 'encoding through the protocol SDK' do
    it 'serializes RUN_STARTED with protocolVersion and RunFinishedEvent with a cancelled outcome' do
      started = RubyLLM::AgUI::Protocol::RunStartedEvent.new(thread_id: 't1', run_id: 'r1')
      started_payload = JSON.parse(encoder.encode(started).sub(/\Adata: /, ''))
      expect(started_payload).to include('type' => 'RUN_STARTED', 'protocolVersion' => '1.0')

      finished = RubyLLM::AgUI::Protocol::RunFinishedEvent.new(
        thread_id: 't1', run_id: 'r1', outcome: RubyLLM::AgUI::Protocol::CancelledOutcome.new
      )
      finished_payload = JSON.parse(encoder.encode(finished).sub(/\Adata: /, ''))
      expect(finished_payload).to include('type' => 'RUN_FINISHED')
      expect(finished_payload['outcome']).to eq('type' => 'cancelled')
    end

    it 'still carries the SDK success and interrupt outcomes unchanged' do
      success = RubyLLM::AgUI::Protocol::RunFinishedEvent.new(
        thread_id: 't1', run_id: 'r1',
        outcome: AgUiProtocol::Core::Events::RunFinishedSuccessOutcome.new
      )
      expect(JSON.parse(encoder.encode(success).sub(/\Adata: /, ''))['outcome']).to eq('type' => 'success')

      interrupt = RubyLLM::AgUI::Protocol::RunFinishedEvent.new(
        thread_id: 't1', run_id: 'r1',
        outcome: AgUiProtocol::Core::Events::RunFinishedInterruptOutcome.new(
          interrupts: [AgUiProtocol::Core::Types::Interrupt.new(id: 'i1', reason: 'tool_approval')]
        )
      )
      expect(JSON.parse(encoder.encode(interrupt).sub(/\Adata: /, ''))['outcome'])
        .to include('type' => 'interrupt')
    end
  end

  describe 'namespace hygiene' do
    it 'does not define or reopen top-level AgUi' do
      expect(described_class.name).to eq('RubyLLM::AgUI::Protocol')
      expect(RubyLLM::AgUI::Protocol::CancelledOutcome.name).to start_with('RubyLLM::AgUI::')
    end
  end
end
