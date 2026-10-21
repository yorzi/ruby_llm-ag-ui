# frozen_string_literal: true

RSpec.describe 'the live provider harness with intercepted HTTP' do
  it 'uses the synthetic OpenRouter configuration and sends bounded requests' do
    config = RubyLLM::Configuration.new
    config.openrouter_api_key = 'offline-fixture'
    config.max_retries = 0
    stub = stub_request(:post, 'https://openrouter.ai/api/v1/chat/completions')
           .with(headers: { 'Authorization' => 'Bearer offline-fixture' },
                 body: hash_including('max_tokens' => 128, 'stream' => true))
           .to_raise(Faraday::TimeoutError)
    chat = LiveHarness.chat(prompt: 'Reply ready.', configuration: config)
    input = RubyLLM::AgUI::Input.parse({ 'threadId' => 't', 'runId' => 'r', 'messages' => [] })
    record = RubyLLM::AgUI::Run.new(chat: chat, input: input, scope: 'fixture',
                                    store: RubyLLM::AgUI::Store::MemoryStore.new).stream(to: StringIO.new)
    expect(record.failure['code']).to eq('transport_timeout')
    expect(stub).to have_been_requested.once
  end

  %w[resolved cancelled].each do |decision|
    it "resumes a real RubyLLM #{decision} answer without publishing its original call twice" do
      config = RubyLLM::Configuration.new
      config.openrouter_api_key = 'offline-fixture'
      config.max_retries = 0
      tool = LiveHarness::FixtureLookup.new
      chat = LiveHarness.chat(prompt: 'Lookup ready.', tool: tool, configuration: config)
      first_delta = { tool_calls: [{ index: 0, id: 'call_fixture', type: 'function',
                                     function: { name: tool.name, arguments: '{"value":"ready"}' } }] }
      stub = stub_request(:post, 'https://openrouter.ai/api/v1/chat/completions')
             .to_return(headers: { 'Content-Type' => 'text/event-stream' }, body: sse_delta(first_delta, 'tool_calls'))
             .then.to_return(headers: { 'Content-Type' => 'text/event-stream' },
                             body: sse_delta({ content: 'ready' }, 'stop'))
      store = RubyLLM::AgUI::Store::MemoryStore.new
      input = RubyLLM::AgUI::Input.parse({ 'threadId' => 't', 'runId' => 'r', 'messages' => [] })
      first = stream(chat, input, store, StringIO.new)
      expect(first).to be_interrupted
      expect(tool.calls).to eq(0)
      resumed = RubyLLM::AgUI::Input.parse(input.to_h.merge(
                                             'runId' => 'resume', 'resume' => [{
                                               'interruptId' => first.interrupts.first.id, 'status' => decision
                                             }]
                                           ))
      output = StringIO.new
      expect(stream(chat, resumed, store, output)).to be_succeeded
      expect(event_types(output)).not_to include('TOOL_CALL_START', 'TOOL_CALL_ARGS', 'TOOL_CALL_END')
      expect(decode_sse(output).find do |event|
        event['type'] == 'TOOL_CALL_RESULT'
      end['toolCallId']).to eq('call_fixture')
      expect(stream(chat, resumed, store, StringIO.new)).to be_succeeded
      expect(tool.calls).to eq(decision == 'resolved' ? 1 : 0)
      expect(stub).to have_been_requested.twice
    end
  end

  def stream(chat, input, store, output)
    RubyLLM::AgUI::Run.new(chat: chat, input: input, scope: 'fixture', store: store).stream(to: output)
  end

  def sse_delta(delta, reason)
    payload = { id: 'fixture', model: 'fixture', choices: [{ index: 0, delta: delta, finish_reason: reason }] }
    "data: #{JSON.generate(payload)}\n\ndata: [DONE]\n\n"
  end
end
