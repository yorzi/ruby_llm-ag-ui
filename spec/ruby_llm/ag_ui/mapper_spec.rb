# frozen_string_literal: true

RSpec.describe RubyLLM::AgUI::Mapper do
  subject(:mapper) { described_class.new(thread_id: 'thread-1', run_id: 'run-1', redact: redact) }

  let(:redact) { RubyLLM::AgUI::Redaction.method(:none) }

  # The emitted event types, which is what the ordering rules are about.
  def types(events)
    events.map(&:type)
  end

  def schema_valid!(events)
    events.each { |event| expect_valid_event(JSON.parse(event.to_json)) }
  end

  describe 'identity' do
    it 'exposes the run it is projecting' do
      expect(mapper.thread_id).to eq('thread-1')
      expect(mapper.run_id).to eq('run-1')
    end
  end

  describe 'streamed text (FR-03)' do
    it 'opens one message, emits one delta per chunk and closes on the message' do
      events = mapper.chunk(chunk(content: 'Hello '))
      events.concat(mapper.chunk(chunk(content: 'world')))
      events.concat(mapper.message(assistant_message(content: 'Hello world')))

      expect(types(events)).to eq(
        %w[STEP_STARTED TEXT_MESSAGE_START TEXT_MESSAGE_CONTENT TEXT_MESSAGE_CONTENT TEXT_MESSAGE_END STEP_FINISHED]
      )
      starts = events.select { |e| e.type == 'TEXT_MESSAGE_START' }
      expect(starts.length).to eq(1)
      expect(starts.first.role).to eq('assistant')
      expect(events.select { |e| e.type == 'TEXT_MESSAGE_CONTENT' }.map(&:delta)).to eq(['Hello ', 'world'])
      expect(events.select { |e| e.type == 'TEXT_MESSAGE_END' }.map(&:message_id)).to eq([starts.first.message_id])
      schema_valid!(events)
    end

    it 'ignores a chunk with no content' do
      expect(mapper.chunk(chunk)).to eq([])
      expect(mapper.chunk(chunk(finish_reason: :stop)).map(&:type)).to eq([])
    end

    it 'scopes the message id to the run, so two runs never collide' do
      other = described_class.new(thread_id: 'thread-1', run_id: 'run-2')
      first = mapper.chunk(chunk(content: 'a')).find { |e| e.type == 'TEXT_MESSAGE_START' }
      second = other.chunk(chunk(content: 'a')).find { |e| e.type == 'TEXT_MESSAGE_START' }
      expect(first.message_id).to start_with('run-1:')
      expect(second.message_id).to start_with('run-2:')
      expect(first.message_id).not_to eq(second.message_id)
    end
  end

  describe 'a provider that does not stream (FR-03)' do
    it 'emits the text from the final message' do
      events = mapper.message(assistant_message(content: 'No chunks here'))
      expect(types(events)).to eq(%w[STEP_STARTED TEXT_MESSAGE_START TEXT_MESSAGE_CONTENT
                                     TEXT_MESSAGE_END STEP_FINISHED])
      expect(events.find { |e| e.type == 'TEXT_MESSAGE_CONTENT' }.delta).to eq('No chunks here')
      schema_valid!(events)
    end

    it 'does not repeat text the stream already delivered' do
      mapper.chunk(chunk(content: 'streamed'))
      events = mapper.message(assistant_message(content: 'streamed'))
      expect(types(events)).not_to include('TEXT_MESSAGE_START', 'TEXT_MESSAGE_CONTENT')
      expect(types(events)).to eq(%w[TEXT_MESSAGE_END STEP_FINISHED])
    end
  end

  describe 'streamed tool calls (FR-03)' do
    it 'emits start on the naming fragment, one delta per fragment, and end at the completion' do
      named = streamed_tool_calls(id: 'call_1', name: 'search', arguments: '{"q":')
      events = []
      events.concat(mapper.chunk(chunk(tool_calls: named)))
      events.concat(mapper.chunk(chunk(tool_calls: streamed_tool_calls(arguments: '"ruby"}'))))
      events.concat(mapper.chunk(chunk(finish_reason: :tool_calls)))

      expect(types(events)).to eq(%w[STEP_STARTED TOOL_CALL_START TOOL_CALL_ARGS TOOL_CALL_ARGS
                                     TOOL_CALL_END STEP_FINISHED])
      start = events.find { |e| e.type == 'TOOL_CALL_START' }
      expect(start.tool_call_id).to eq('call_1')
      expect(start.tool_call_name).to eq('search')
      expect(events.select { |e| e.type == 'TOOL_CALL_ARGS' }.map(&:delta)).to eq(['{"q":', '"ruby"}'])
      schema_valid!(events)
    end

    it 'does not re-synthesise the arguments from the final message' do
      mapper.chunk(chunk(tool_calls: streamed_tool_calls(id: 'call_1', name: 'search', arguments: '{"q":"ruby"}')))
      events = mapper.message(
        assistant_message(
          tool_calls: { 'call_1' => tool_call(id: 'call_1', name: 'search', arguments: { 'q' => 'ruby' }) }
        )
      )
      expect(types(events)).to eq(%w[TOOL_CALL_END STEP_FINISHED])
    end

    it 'buffers argument fragments that arrive before the call is named' do
      events = mapper.chunk(chunk(tool_calls: streamed_tool_calls(arguments: '{"q":')))
      expect(types(events)).to eq([])

      named = streamed_tool_calls(id: 'call_1', name: 'search', arguments: '"ruby"}')
      events.concat(mapper.chunk(chunk(tool_calls: named)))
      expect(types(events)).to eq(%w[STEP_STARTED TOOL_CALL_START TOOL_CALL_ARGS TOOL_CALL_ARGS])
      expect(events.select { |e| e.type == 'TOOL_CALL_ARGS' }.map(&:delta)).to eq(['{"q":', '"ruby"}'])
      schema_valid!(events)
    end

    it 'closes an open text message before the tool call starts' do
      events = mapper.chunk(chunk(content: 'Let me look'))
      later = streamed_tool_calls(id: 'call_1', name: 'search', arguments: '{}')
      events.concat(mapper.chunk(chunk(tool_calls: later)))
      expect(types(events)).to eq(%w[STEP_STARTED TEXT_MESSAGE_START TEXT_MESSAGE_CONTENT
                                     TEXT_MESSAGE_END TOOL_CALL_START TOOL_CALL_ARGS])
      text_start = events.find { |e| e.type == 'TEXT_MESSAGE_START' }
      tool_start = events.find { |e| e.type == 'TOOL_CALL_START' }
      expect(tool_start.parent_message_id).to eq(text_start.message_id)
      schema_valid!(events)
    end
  end

  describe '#before_tool_call (FR-03)' do
    it 'only closes a call the stream already reported' do
      mapper.chunk(chunk(tool_calls: streamed_tool_calls(id: 'call_1', name: 'search', arguments: '{}')))
      events = mapper.before_tool_call(tool_call(id: 'call_1', name: 'search', arguments: { 'q' => 'ruby' }))
      expect(types(events)).to eq(%w[TOOL_CALL_END])
    end

    it 'opens and closes a call the provider never streamed' do
      events = mapper.before_tool_call(tool_call(id: 'call_1', name: 'search', arguments: { 'q' => 'ruby' }))
      expect(types(events)).to eq(%w[STEP_STARTED TOOL_CALL_START TOOL_CALL_ARGS TOOL_CALL_END])
      expect(events.find { |e| e.type == 'TOOL_CALL_ARGS' }.delta).to eq('{"q":"ruby"}')
      schema_valid!(events)
    end

    it 'does not open the same call twice' do
      first = mapper.before_tool_call(tool_call(id: 'call_1', name: 'search', arguments: { 'q' => 'ruby' }))
      second = mapper.before_tool_call(tool_call(id: 'call_1', name: 'search', arguments: { 'q' => 'ruby' }))
      expect(types(first)).to include('TOOL_CALL_START')
      expect(types(second)).to eq([])
    end
  end

  describe 'tool results (FR-03) and redaction (FR-05)' do
    let(:redact) { nil }

    before { RubyLLM::AgUI.config.redact = RubyLLM::AgUI::Redaction.method(:none) }

    it 'answers the call with the protocol tool result shape' do
      events = mapper.message(tool_message(content: 'order 42 cancelled', tool_call_id: 'call_1'))
      expect(types(events)).to eq(%w[STEP_STARTED TOOL_CALL_RESULT])
      result = events.last
      expect(result.tool_call_id).to eq('call_1')
      expect(result.message_id).to eq('run-1:tool:call_1')
      expect(result.content).to eq('order 42 cancelled')
      expect(result.role).to eq('tool')
      schema_valid!(events)
    end

    it 'holds the tool round open until the next completion closes its step' do
      events = mapper.message(tool_message(content: 'ok', tool_call_id: 'call_1'))
      events.concat(mapper.chunk(chunk(content: 'Done')))
      expect(types(events)).to eq(%w[STEP_STARTED TOOL_CALL_RESULT STEP_FINISHED STEP_STARTED
                                     TEXT_MESSAGE_START TEXT_MESSAGE_CONTENT])
      schema_valid!(events)
    end

    context 'with the default policy' do
      let(:redact) { RubyLLM::AgUI::Redaction.method(:default) }

      it 'keeps the shape and withholds the content' do
        events = mapper.message(tool_message(content: 'sk-live-secret', tool_call_id: 'call_1'))
        expect(events.last.content).to eq(RubyLLM::AgUI::Redaction::PLACEHOLDER)
        expect(JSON.generate(events.last.to_h)).not_to include('sk-live-secret')
      end

      it 'warns once that the host has not chosen a policy' do
        logger = instance_double(Logger, warn: nil)
        warming = described_class.new(thread_id: 't', run_id: 'r', redact: RubyLLM::AgUI::Redaction.method(:default),
                                      logger: logger)
        2.times { warming.message(tool_message(content: 'x', tool_call_id: 'call_1')) }
        expect(logger).to have_received(:warn).once
      end
    end
  end

  describe 'private reasoning stays private (FR-03 negative case)' do
    it 'never emits a reasoning event, even when a chunk carries thinking' do
      thinking = RubyLLM::Thinking.build(text: 'the secret plan')
      events = mapper.chunk(chunk(content: 'ok', thinking: thinking))
      events.concat(mapper.close)
      expect(types(events)).not_to include(a_string_matching(/REASONING|THINKING/))
      expect(JSON.generate(events.map(&:to_h))).not_to include('secret plan')
    end
  end

  describe '#close (FR-05)' do
    it 'closes an open text message and its step before the terminal event' do
      mapper.chunk(chunk(content: 'partial'))
      expect(types(mapper.close)).to eq(%w[TEXT_MESSAGE_END STEP_FINISHED])
      schema_valid!(mapper.close)
    end

    it 'closes a streamed tool call the provider never ended' do
      mapper.chunk(chunk(tool_calls: streamed_tool_calls(id: 'call_1', name: 'search', arguments: '{}')))
      expect(types(mapper.close)).to eq(%w[TOOL_CALL_END STEP_FINISHED])
      schema_valid!(mapper.close)
    end

    it 'is idempotent' do
      mapper.chunk(chunk(content: 'partial'))
      mapper.close
      expect(mapper.close).to eq([])
    end

    it 'closes nothing when nothing is open' do
      expect(mapper.close).to eq([])
    end
  end

  describe 'a multi-step turn (FR-03)' do
    it 'emits a schema-valid run for text, a streamed tool call, a result and a second completion' do
      streamed = streamed_tool_calls(id: 'call_1', name: 'search', arguments: '{"q":"ruby"}')
      invoked = tool_call(id: 'call_1', name: 'search', arguments: { 'q' => 'ruby' })

      events = []
      events.concat(mapper.chunk(chunk(content: 'Checking')))
      events.concat(mapper.chunk(chunk(tool_calls: streamed)))
      events.concat(mapper.message(assistant_message(tool_calls: { 'call_1' => invoked })))
      events.concat(mapper.before_tool_call(invoked))
      events.concat(mapper.message(tool_message(content: '3 results', tool_call_id: 'call_1')))
      events.concat(mapper.chunk(chunk(content: 'Found three.')))
      events.concat(mapper.message(assistant_message(content: 'Found three.')))
      events.concat(mapper.close)

      expect(types(events)).to eq(
        %w[
          STEP_STARTED TEXT_MESSAGE_START TEXT_MESSAGE_CONTENT TEXT_MESSAGE_END TOOL_CALL_START TOOL_CALL_ARGS
          TOOL_CALL_END STEP_FINISHED STEP_STARTED TOOL_CALL_RESULT STEP_FINISHED STEP_STARTED TEXT_MESSAGE_START
          TEXT_MESSAGE_CONTENT TEXT_MESSAGE_END STEP_FINISHED
        ]
      )
      schema_valid!(events)
    end
  end

  describe 'a closed mapper (a second turn on the same chat)' do
    it 'maps nothing after the run it projected has ended' do
      mapper.chunk(chunk(content: 'First turn.'))
      mapper.message(assistant_message(content: 'First turn.'))
      mapper.close

      expect(mapper.chunk(chunk(content: 'Second turn.'))).to eq([])
      expect(mapper.message(assistant_message(content: 'Second turn.'))).to eq([])
      expect(mapper.message(tool_message(content: 'result', tool_call_id: 'call_1'))).to eq([])
      expect(mapper.before_tool_call(tool_call(id: 'call_1', name: 'search', arguments: {}))).to eq([])
      expect(mapper.close).to eq([])
    end

    it 'does not leak the previous run ids into the next run stream' do
      first = mapper.chunk(chunk(content: 'First turn.')) + mapper.close

      mapper.chunk(chunk(content: 'Second turn.'))

      expect(types(first)).to eq(
        %w[STEP_STARTED TEXT_MESSAGE_START TEXT_MESSAGE_CONTENT TEXT_MESSAGE_END STEP_FINISHED]
      )
    end
  end
end
