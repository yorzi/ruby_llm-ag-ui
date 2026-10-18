# frozen_string_literal: true

RSpec.describe RubyLLM::AgUI::Coverage do
  describe 'the pinned 1.0 schema event types' do
    it 'lists all 31 event types the Event union defines' do
      expect(described_class::SCHEMA_EVENT_TYPES.size).to eq(31)
      expect(described_class::SCHEMA_EVENT_TYPES.uniq.size).to eq(31)
    end

    it 'assigns every event type a known status and a note (FR-02)' do
      described_class.entries.each do |entry|
        expect(described_class::STATUSES).to include(entry[:status])
        expect(entry[:note]).to be_a(String)
        expect(entry[:note]).not_to be_empty
      end
    end

    it 'assigns every event type a family' do
      described_class.entries.each do |entry|
        expect(described_class::FAMILIES.values).to include(entry[:family])
      end
    end
  end

  describe 'the ag-ui-protocol enum comparison (EV-06)' do
    it 'reports the five legacy THINKING types as SDK-only' do
      expect(described_class.sdk_only_event_types).to match_array(described_class::LEGACY_SDK_ONLY)
    end

    it 'reports the three SUBAGENT types as schema-only' do
      expect(described_class.schema_only_event_types).to match_array(
        %w[SUBAGENT_STARTED SUBAGENT_FINISHED SUBAGENT_ERROR]
      )
    end

    it 'does not count a legacy THINKING type as 1.0 coverage' do
      entry_types = described_class.entries.map { |entry| entry[:type] }
      expect(entry_types).not_to include(*described_class::LEGACY_SDK_ONLY)
    end

    it 'reports STATE_SNAPSHOT as produced, because a reconnect serves it (FR-05)' do
      entry = described_class.entries.find { |candidate| candidate[:type] == 'STATE_SNAPSHOT' }
      expect(entry[:status]).to eq(:produced)
    end
  end

  describe 'the SDK gap list' do
    it 'documents the cancelled outcome, the run-start version, the parser and subagents' do
      expect(described_class::GAPS.map { |gap| gap[:id] }).to eq(%w[SDK-GAP-01 SDK-GAP-02 SDK-GAP-03 SDK-GAP-04])
    end

    it 'gives every gap a handling note and an upstream link' do
      described_class::GAPS.each do |gap|
        expect(gap[:gem_handling]).not_to be_empty
        expect(gap[:upstream]).to start_with('https://github.com/ag-ui-protocol/ag-ui')
      end
    end
  end
end
