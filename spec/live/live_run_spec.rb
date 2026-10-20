# frozen_string_literal: true

# Provider calls are opt-in. Load credentials through the environment or an
# untracked env file, then run RUBY_LLM_LIVE=1 bundle exec rspec spec/live.
# The offline context checks the same run setup without provider credentials.
RSpec.describe RubyLLM::AgUI::Run do
  subject(:run) do
    described_class.new(chat: chat, input: input, scope: 'live:actor-1',
                        store: RubyLLM::AgUI::Store::MemoryStore.new)
  end

  let(:prompt) { 'Reply with exactly one word: ready' }
  let(:sse) { StringIO.new }
  let(:input) do
    RubyLLM::AgUI::Input.parse(
      {
        'threadId' => 'live-thread', 'runId' => "live-run-#{SecureRandom.hex(4)}", 'protocolVersion' => '1.0',
        'messages' => [{ 'id' => 'm1', 'role' => 'user', 'content' => prompt }]
      }
    )
  end

  describe 'the live harness without a provider' do
    let(:chat) do
      FakeChat.new do |fake|
        fake.stream(content: 'ready')
        fake.reply(content: 'ready')
      end
    end

    it 'reserves an actor-scoped run and reaches the chat' do
      record = run.stream(to: sse)
      expect(record).to be_succeeded
      expect(record.scope).to eq('live:actor-1')
      expect(event_types(sse)).to include('TEXT_MESSAGE_CONTENT', 'RUN_FINISHED')
    end
  end

  describe 'against a live provider' do
    before do
      skip 'set RUBY_LLM_LIVE=1 and OPENROUTER_API_KEY for bounded live checks' unless ENV['RUBY_LLM_LIVE'] == '1'
    end

    let(:chat) { LiveHarness.chat(prompt: prompt) }

    it 'streams one real turn as a valid, successful AG-UI run' do
      expect(run.stream(to: sse)).to be_succeeded
      expect(event_types(sse)).to include('RUN_STARTED', 'TEXT_MESSAGE_START', 'TEXT_MESSAGE_END', 'RUN_FINISHED')
      expect(event_types(sse).last).to eq('RUN_FINISHED')
      decode_sse(sse).each { |event| expect_valid_event(event) }
    end

    it 'approves the original synthetic tool and reconnects without running it again' do
      tool = LiveHarness::FixtureLookup.new
      provider_chat = LiveHarness.chat(prompt: 'Call fixture_lookup with value ready, then say ready.', tool: tool)
      store = RubyLLM::AgUI::Store::MemoryStore.new
      first = stream(provider_chat, input, store, sse)
      expect(first).to be_interrupted
      expect(tool.calls).to eq(0)
      call = decode_sse(sse).find { |event| event['type'] == 'TOOL_CALL_START' }
      resumed_input = RubyLLM::AgUI::Input.parse(input.to_h.merge(
                                                   'runId' => "#{input.run_id}-resume",
                                                   'resume' => [{ 'interruptId' => first.interrupts.first.id,
                                                                  'status' => 'resolved' }]
                                                 ))
      output = StringIO.new
      expect(stream(provider_chat, resumed_input, store, output)).to be_succeeded
      events = decode_sse(output)
      expect(events.find { |event| event['type'] == 'TOOL_CALL_RESULT' }['toolCallId']).to eq(call['toolCallId'])
      expect(events.map { |event| event['type'] }).not_to include('TOOL_CALL_START')
      expect(output.string).not_to include('fixture-secret')
      events.each { |event| expect_valid_event(event) }
      expect(stream(provider_chat, resumed_input, store, StringIO.new)).to be_succeeded
      expect(tool.calls).to eq(1)
    end

    def stream(chat, parsed_input, store, output)
      RubyLLM::AgUI::Run.new(chat: chat, input: parsed_input, scope: 'live:actor-1', store: store).stream(to: output)
    end
  end
end
