# frozen_string_literal: true

RSpec.describe RubyLLM::AgUI do
  describe RubyLLM::AgUI::Configuration do
    subject(:config) { described_class.new }

    it 'has a pinned protocol version and bounded input limits' do
      expect(config.protocol_version).to eq('1.0')
      expect(config.max_input_bytes).to eq(256_000)
      expect(config.max_messages).to eq(500)
      expect(config.max_tools).to eq(64)
      expect(config.max_context).to eq(64)
    end

    it 'defaults to conservative, opt-in behavior' do
      expect(config.interrupt_ttl).to eq(900)
      expect(config.emit_tool_progress).to be(false)
      expect(config.allow_client_history).to be(false)
      expect(config.redact).to be_nil
      expect(config.run_store).to be_nil
    end

    it 'refuses to hand out a missing run store' do
      expect { config.run_store! }.to raise_error(RubyLLM::AgUI::ConfigurationError, /run_store/)
    end

    it 'returns a UTC time from the default clock' do
      expect(config.clock.call).to be_a(Time)
      expect(config.clock.call).to be_utc
    end

    it 'reports a snapshot without secrets' do
      expect(config.to_h.keys).to eq(
        %i[run_store redact protocol_version max_input_bytes max_messages max_tools
           max_context emit_tool_progress interrupt_ttl allow_client_history]
      )
      expect(config.to_h[:redact]).to be(false)
    end
  end

  describe '.configure' do
    it 'memoizes and yields the configuration' do
      yielded = nil
      described_class.configure { |config| yielded = config }
      expect(yielded).to be(described_class.config)
      expect(described_class.config).to be_a(RubyLLM::AgUI::Configuration)
    end
  end

  describe '.reset_configuration!' do
    it 'restores the defaults' do
      described_class.config.max_input_bytes = 1
      described_class.reset_configuration!
      expect(described_class.config.max_input_bytes).to eq(256_000)
    end
  end
end
