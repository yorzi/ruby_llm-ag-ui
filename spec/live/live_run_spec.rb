# frozen_string_literal: true

# The only spec that talks to a model provider, and it is opt-in:
#
#   RUBY_LLM_LIVE=1 OPENAI_API_KEY=... bundle exec rspec spec/live
#
# It is skipped by default, so `bundle exec rspec` stays offline and needs no
# credentials. What it checks that the fakes cannot: a real provider's chunks
# arrive in shapes the mapper accepts, and a real chat completes as a success
# outcome with schema-valid events.
RSpec.describe RubyLLM::AgUI::Run do
  describe 'against a live provider' do
    before do
      skip 'set RUBY_LLM_LIVE=1 (and a provider key) to run the live checks' unless ENV['RUBY_LLM_LIVE']
    end

    let(:model) { ENV.fetch('RUBY_LLM_LIVE_MODEL', 'gpt-4o-mini') }
    let(:prompt) { 'Reply with exactly one word: ready' }
    let(:sse) { StringIO.new }

    def input
      RubyLLM::AgUI::Input.parse(
        {
          'threadId' => 'live-thread', 'runId' => "live-run-#{SecureRandom.hex(4)}", 'protocolVersion' => '1.0',
          'messages' => [{ 'id' => 'm1', 'role' => 'user', 'content' => prompt }]
        }
      )
    end

    def chat
      RubyLLM::Chat.new(model: model).add_message(role: :user, content: prompt)
    end

    it 'streams one real turn as a valid, successful AG-UI run' do
      record = described_class.new(
        chat: chat, input: input, store: RubyLLM::AgUI::Store::MemoryStore.new
      ).stream(to: sse)

      expect(record).to be_succeeded
      expect(event_types(sse)).to include('RUN_STARTED', 'TEXT_MESSAGE_START', 'TEXT_MESSAGE_END', 'RUN_FINISHED')
      expect(event_types(sse).last).to eq('RUN_FINISHED')

      decode_sse(sse).each { |event| expect_valid_event(event) }
    end
  end
end
