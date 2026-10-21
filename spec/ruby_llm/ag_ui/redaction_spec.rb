# frozen_string_literal: true

RSpec.describe RubyLLM::AgUI::Redaction do
  describe '.apply' do
    it 'passes the kind and payload to a two-argument policy' do
      policy = ->(kind, payload) { "#{kind}:#{payload}" }
      expect(described_class.apply(policy, :tool_result, 'value')).to eq('tool_result:value')
    end

    it 'passes only the payload to a one-argument policy' do
      expect(described_class.apply(->(payload) { "#{payload}!" }, :tool_result, 'value')).to eq('value!')
    end

    it 'accepts a policy object that only responds to call' do
      two = Class.new { def call(kind, payload) = [kind, payload] }.new
      one = Module.new { def self.call(payload) = payload.reverse }
      expect(described_class.apply(two, :tool_progress, 'value')).to eq([:tool_progress, 'value'])
      expect(described_class.apply(one, :tool_result, 'value')).to eq('eulav')
    end
  end
end
