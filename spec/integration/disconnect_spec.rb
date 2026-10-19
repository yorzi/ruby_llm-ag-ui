# frozen_string_literal: true

RSpec.describe 'Transport lifecycle' do
  let(:store) { RubyLLM::AgUI::Store::MemoryStore.new }
  let(:input) { RubyLLM::AgUI::Input.parse({ 'threadId' => 't', 'runId' => 'r', 'messages' => [] }) }

  def run(chat, to:)
    RubyLLM::AgUI::Run.new(chat: chat, input: input, scope: 'actor:1', store: store,
                           emit_tool_progress: true).stream(to: to)
  end

  def reconnect
    output = StringIO.new
    run(FakeChat.new { raise 'reconnect must not execute' }, to: output)
    decode_sse(output)
  end

  %w[RUN_STARTED TEXT_MESSAGE_CONTENT ACTIVITY_SNAPSHOT STEP_FINISHED RUN_FINISHED].each do |event|
    it "finishes once after the transport drops at #{event}" do
      effects = 0
      chat = FakeChat.new do |fake|
        fake.stream(content: 'hello')
        fake.call_tool(id: 'c', name: 'fixture', arguments: {})
        effects += 1
        fake.progress(RubyLLM::ToolCall.new(id: 'c', name: 'fixture', arguments: {}), value: 1)
        fake.tool_result(content: 'done', tool_call_id: 'c')
      end
      sink = DisconnectStream.new(at: event)

      expect(run(chat, to: sink)).to be_succeeded
      expect(effects).to eq(1)
      expect(sink.failures).to eq(1)
      events = reconnect
      expect(events.map { |entry| entry['type'] }).to eq(%w[RUN_STARTED STATE_SNAPSHOT RUN_FINISHED])
      expect(events.last['outcome']).to eq('type' => 'success')
      events.each { |entry| expect_valid_event(entry) }
    end
  end

  it 'keeps cancellation truthful after a flush fails' do
    chat = FakeChat.new do |fake|
      fake.stream(content: 'partial')
      fake.cancel!
    end
    sink = DisconnectStream.new(at: 'TEXT_MESSAGE_CONTENT', flush: true)

    expect(run(chat, to: sink)).to be_cancelled
    expect(reconnect.last['outcome']).to eq('type' => 'cancelled')
    expect(sink.failures).to eq(1)
  end

  it 'keeps the sanitized provider failure after the client leaves' do
    chat = FakeChat.new do |fake|
      fake.stream(content: 'partial')
      raise Timeout::Error, 'private provider detail'
    end
    expect(run(chat, to: DisconnectStream.new(at: 'RUN_STARTED'))).to be_failed
    expect(reconnect.last).to include('type' => 'RUN_ERROR', 'code' => 'transport_timeout')
    expect(reconnect.last.to_s).not_to include('private')
  end
end
