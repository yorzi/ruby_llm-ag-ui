# frozen_string_literal: true

RSpec.describe RubyLLM::AgUI::Canonical do
  describe '.dump' do
    it 'sorts object keys recursively for a stable string' do
      a = { 'b' => 1, 'a' => { 'd' => 2, 'c' => 3 } }
      b = { 'a' => { 'c' => 3, 'd' => 2 }, 'b' => 1 }
      expect(described_class.dump(a)).to eq(described_class.dump(b))
    end

    it 'preserves array order' do
      expect(described_class.dump([2, 1])).to eq('[2,1]')
      expect(described_class.dump([2, 1])).not_to eq(described_class.dump([1, 2]))
    end

    it 'sorts short keys first, matching RubyLLM argument canonicalization' do
      expect(described_class.dump({ 'long_key' => 1, 'b' => 2 })).to eq('{"b":2,"long_key":1}')
    end
  end

  describe '.digest' do
    it 'is a SHA-256 hex digest' do
      expect(described_class.digest('value')).to match(/\A[0-9a-f]{64}\z/)
    end

    it 'is equal for equal canonical values' do
      expect(described_class.digest({ 'a' => 1, 'b' => 2 })).to eq(described_class.digest({ 'b' => 2, 'a' => 1 }))
    end
  end
end
