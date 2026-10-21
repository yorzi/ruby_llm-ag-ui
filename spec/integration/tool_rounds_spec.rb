# frozen_string_literal: true

RSpec.describe 'consecutive streamed tool rounds with intercepted HTTP' do
  let(:tool) do
    Class.new(RubyLLM::Tool) do
      def self.name = 'Lookup'

      description 'Return a synthetic fixture value.'
      parameter :query, description: 'The fixture query.'

      def execute(query:) = "found #{query}"
    end.new
  end

  let(:chat) do
    configuration = RubyLLM::Configuration.new
    configuration.openrouter_api_key = 'offline-fixture'
    configuration.max_retries = 0
    RubyLLM::Context.new(configuration).chat(model: 'fixture-model', provider: :openrouter,
                                             assume_model_exists: true).tap do |instance|
      instance.with_tools(tool)
      instance.add_message(role: :user, content: 'fixture')
    end
  end

  # Chat Completions restarts tool-call indexes at 0 in every response, and
  # sends the id and name only on a call's first fragment.
  def tool_round(id, query)
    sse([{ tool_calls: [{ index: 0, id: id, type: 'function', function: { name: tool.name, arguments: '' } }] },
         { tool_calls: [{ index: 0, function: { arguments: %({"query":"#{query}"}) } }] }], 'tool_calls')
  end

  def sse(deltas, reason)
    frames = deltas.map { |delta| { id: 'fixture', model: 'fixture', choices: [{ index: 0, delta: delta }] } }
    frames << { id: 'fixture', model: 'fixture', choices: [{ index: 0, delta: {}, finish_reason: reason }] }
    "#{frames.map { |frame| "data: #{JSON.generate(frame)}\n\n" }.join}data: [DONE]\n\n"
  end

  it 'opens each round call once and sends its arguments only to that open call' do
    headers = { 'Content-Type' => 'text/event-stream' }
    stub_request(:post, 'https://openrouter.ai/api/v1/chat/completions')
      .to_return(headers: headers, body: tool_round('call_a', 'one'))
      .then.to_return(headers: headers, body: tool_round('call_b', 'two'))
      .then.to_return(headers: headers, body: sse([{ content: 'done' }], 'stop'))
    input = RubyLLM::AgUI::Input.parse({ 'threadId' => 't', 'runId' => 'r', 'messages' => [] })
    output = StringIO.new

    record = RubyLLM::AgUI::Run.new(chat: chat, input: input, scope: 'actor:1',
                                    store: RubyLLM::AgUI::Store::MemoryStore.new,
                                    redact: RubyLLM::AgUI::Redaction.method(:none)).stream(to: output)

    expect(record).to be_succeeded
    events = decode_sse(output)
    events.each { |event| expect_valid_event(event) }
    calls = events.select { |event| event['type'].start_with?('TOOL_CALL_') && event['type'] != 'TOOL_CALL_RESULT' }
    expect(calls.map { |event| [event['type'], event['toolCallId'], event['delta']].compact }).to eq(
      [
        ['TOOL_CALL_START', 'call_a'], ['TOOL_CALL_ARGS', 'call_a', '{"query":"one"}'], ['TOOL_CALL_END', 'call_a'],
        ['TOOL_CALL_START', 'call_b'], ['TOOL_CALL_ARGS', 'call_b', '{"query":"two"}'], ['TOOL_CALL_END', 'call_b']
      ]
    )
  end
end
