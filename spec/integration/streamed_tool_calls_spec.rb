# frozen_string_literal: true

# Each provider protocol streams tool calls in its own shape. These run a real
# RubyLLM chat against intercepted HTTP and check what an AG-UI client would
# assemble: one start per call, arguments only for an open call, and argument
# deltas that concatenate to the JSON the tool received.
RSpec.describe 'streamed tool calls with intercepted HTTP' do
  let(:tool) do
    Class.new(RubyLLM::Tool) do
      def self.name = 'Lookup'

      description 'Return a synthetic fixture value.'
      parameter :query, description: 'The fixture query.'

      attr_reader :queries

      def execute(query:)
        (@queries ||= []) << query
        "found #{query}"
      end
    end.new
  end

  let(:headers) { { 'Content-Type' => 'text/event-stream' } }

  def chat_for(provider, model: 'fixture-model')
    configuration = RubyLLM::Configuration.new
    configuration.public_send(:"#{provider}_api_key=", 'offline-fixture')
    configuration.max_retries = 0
    RubyLLM::Context.new(configuration).chat(model: model, provider: provider,
                                             assume_model_exists: true).tap do |instance|
      instance.with_tools(tool)
      instance.add_message(role: :user, content: 'fixture')
    end
  end

  def run(chat)
    output = StringIO.new
    input = RubyLLM::AgUI::Input.parse({ 'threadId' => 't', 'runId' => 'r', 'messages' => [] })
    record = RubyLLM::AgUI::Run.new(chat: chat, input: input, scope: 'actor:1',
                                    store: RubyLLM::AgUI::Store::MemoryStore.new,
                                    redact: RubyLLM::AgUI::Redaction.method(:none)).stream(to: output)
    expect(record).to be_succeeded
    decode_sse(output).each { |event| expect_valid_event(event) }
  end

  # The call events a client sees, with each call's assembled arguments parsed.
  def calls(events)
    events.select { |event| %w[TOOL_CALL_START TOOL_CALL_ARGS TOOL_CALL_END].include?(event['type']) }
          .slice_before { |event| event['type'] == 'TOOL_CALL_START' }
          .map { |call| summarize(call) }
  end

  def summarize(call)
    arguments = call.filter_map { |event| event['delta'] }.join
    [call.map { |event| event['toolCallId'] }.uniq, call.map { |event| event['type'] }.uniq, JSON.parse(arguments)]
  end

  describe 'Chat Completions' do
    # Indexes restart at 0 in every response, and only a call's first fragment
    # carries its id and name.
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
      stub_request(:post, 'https://openrouter.ai/api/v1/chat/completions')
        .to_return(headers: headers, body: tool_round('call_a', 'one'))
        .then.to_return(headers: headers, body: tool_round('call_b', 'two'))
        .then.to_return(headers: headers, body: sse([{ content: 'done' }], 'stop'))

      expect(calls(run(chat_for(:openrouter)))).to eq(
        [
          [['call_a'], %w[TOOL_CALL_START TOOL_CALL_ARGS TOOL_CALL_END], { 'query' => 'one' }],
          [['call_b'], %w[TOOL_CALL_START TOOL_CALL_ARGS TOOL_CALL_END], { 'query' => 'two' }]
        ]
      )
      expect(tool.queries).to eq(%w[one two])
    end
  end

  describe 'Anthropic Messages' do
    def event(type, data = {})
      "event: #{type}\ndata: #{JSON.generate(data.merge(type: type))}\n\n"
    end

    def response(*blocks, stop_reason)
      message = { id: 'fixture', type: 'message', role: 'assistant', model: 'fixture-model', content: [],
                  usage: { input_tokens: 1, output_tokens: 1 } }
      event('message_start', message: message) + blocks.join +
        event('message_delta', delta: { stop_reason: stop_reason }, usage: { output_tokens: 1 }) +
        event('message_stop')
    end

    # A tool_use block opens with an empty input object, then streams its
    # arguments as partial JSON.
    def tool_block(id, query)
      event('content_block_start', index: 0, content_block: { type: 'tool_use', id: id, name: tool.name, input: {} }) +
        event('content_block_delta', index: 0, delta: { type: 'input_json_delta', partial_json: '{"query":' }) +
        event('content_block_delta', index: 0, delta: { type: 'input_json_delta', partial_json: %("#{query}"}) }) +
        event('content_block_stop', index: 0)
    end

    def text_block(text)
      event('content_block_start', index: 0, content_block: { type: 'text', text: '' }) +
        event('content_block_delta', index: 0, delta: { type: 'text_delta', text: text }) +
        event('content_block_stop', index: 0)
    end

    it 'sends partial JSON arguments without the empty input that opened the block' do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(headers: headers, body: response(tool_block('toolu_a', 'one'), 'tool_use'))
        .then.to_return(headers: headers, body: response(text_block('done'), 'end_turn'))

      expect(calls(run(chat_for(:anthropic)))).to eq(
        [[['toolu_a'], %w[TOOL_CALL_START TOOL_CALL_ARGS TOOL_CALL_END], { 'query' => 'one' }]]
      )
      expect(tool.queries).to eq(%w[one])
    end
  end

  describe 'Gemini' do
    # Gemini sends each call whole, with its arguments as a parsed object.
    def response(parts, finish_reason)
      payload = { candidates: [{ content: { role: 'model', parts: parts }, finishReason: finish_reason }],
                  modelVersion: 'fixture-model', usageMetadata: { promptTokenCount: 1, candidatesTokenCount: 1 } }
      "data: #{JSON.generate(payload)}\n\n"
    end

    it 'sends a whole call object as JSON arguments' do
      url = 'https://generativelanguage.googleapis.com/v1beta/models/fixture-model:streamGenerateContent?alt=sse'
      stub_request(:post, url)
        .to_return(headers: headers,
                   body: response([{ functionCall: { name: tool.name, args: { query: 'one' } } }], 'STOP'))
        .then.to_return(headers: headers, body: response([{ text: 'done' }], 'STOP'))

      found = calls(run(chat_for(:gemini)))
      expect(found.size).to eq(1)
      call_ids, types, arguments = found.first
      expect(call_ids.size).to eq(1)
      expect(types).to eq(%w[TOOL_CALL_START TOOL_CALL_ARGS TOOL_CALL_END])
      expect(arguments).to eq('query' => 'one')
      expect(tool.queries).to eq(%w[one])
    end
  end
end
