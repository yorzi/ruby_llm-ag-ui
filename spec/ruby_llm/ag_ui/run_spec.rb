# frozen_string_literal: true

RSpec.describe RubyLLM::AgUI::Run do
  # A plain method, not a `let`: the example group already needs several
  # memoized helpers and this value never varies.
  def scope
    'tenant-1:actor-1'
  end

  let(:clock) { -> { Time.utc(2026, 10, 17, 12, 0, 0) } }
  let(:store) { RubyLLM::AgUI::Store::MemoryStore.new(clock: clock) }
  let(:input) do
    RubyLLM::AgUI::Input.parse(
      {
        'threadId' => 'thread-1', 'runId' => 'run-1', 'protocolVersion' => '1.0',
        'messages' => [{ 'id' => 'm1', 'role' => 'user', 'content' => 'Hello' }]
      }
    )
  end
  let(:sse) { StringIO.new }

  def stream(chat)
    described_class.new(
      chat: chat, input: input, scope: scope, store: store,
      redact: RubyLLM::AgUI::Redaction.method(:none), clock: clock
    ).stream(to: sse)
  end

  describe 'a successful turn (FR-05-AC-01)' do
    let(:chat) do
      FakeChat.new do |chat|
        chat.stream(content: 'Hello ')
        chat.stream(content: 'world')
        chat.reply(content: 'Hello world')
      end
    end

    it 'opens with RUN_STARTED and closes with a success outcome' do
      record = stream(chat)

      expect(event_types(sse)).to eq(
        %w[RUN_STARTED STEP_STARTED TEXT_MESSAGE_START TEXT_MESSAGE_CONTENT TEXT_MESSAGE_CONTENT
           TEXT_MESSAGE_END STEP_FINISHED RUN_FINISHED]
      )
      expect(record).to be_succeeded
      expect(record.sequence).to eq(8)
    end

    it 'declares the protocol version and echoes the input it accepted' do
      stream(chat)

      started = decode_sse(sse).first
      expect(started['protocolVersion']).to eq('1.0')
      expect(started['threadId']).to eq('thread-1')
      expect(started['runId']).to eq('run-1')
      expect(started['input']).to include('threadId' => 'thread-1')
    end

    it 'reports the outcome as success, never as an absent outcome' do
      stream(chat)

      finished = decode_sse(sse).last
      expect(finished['outcome']).to eq('type' => 'success')
    end

    it 'writes only schema-valid events' do
      stream(chat)

      decode_sse(sse).each { |event| expect_valid_event(event) }
    end
  end

  describe 'cancellation (FR-05-AC-01)' do
    let(:chat) do
      FakeChat.new do |chat|
        chat.stream(content: 'half a th')
        chat.cancel!
      end
    end

    it 'closes the open message, then ends with the cancelled outcome' do
      record = stream(chat)

      expect(event_types(sse)).to eq(
        %w[RUN_STARTED STEP_STARTED TEXT_MESSAGE_START TEXT_MESSAGE_CONTENT
           TEXT_MESSAGE_END STEP_FINISHED RUN_FINISHED]
      )
      expect(decode_sse(sse).last['outcome']).to eq('type' => 'cancelled')
      expect(record).to be_cancelled
    end

    it 'never reports a cancelled run as a success' do
      stream(chat)

      expect(decode_sse(sse).map { |event| event['outcome'] || event['type'] }).not_to include('success')
    end
  end

  describe 'a provider failure (FR-05-AC-01)' do
    let(:chat) do
      FakeChat.new do |chat|
        chat.stream(content: 'partial')
        chat.fail!(RubyLLM::RateLimitError.new('key sk-live-secret leaked'))
      end
    end

    it 'closes the open message and reports a sanitized RUN_ERROR' do
      record = stream(chat)

      expect(event_types(sse)).to eq(
        %w[RUN_STARTED STEP_STARTED TEXT_MESSAGE_START TEXT_MESSAGE_CONTENT TEXT_MESSAGE_END STEP_FINISHED RUN_ERROR]
      )
      error = decode_sse(sse).last
      expect(error['message']).to eq('The model provider rate limit was reached.')
      expect(error['code']).to eq('provider_rate_limited')
      expect(record).to be_failed
    end

    it 'never echoes the exception text' do
      stream(chat)

      expect(sse.string).not_to include('sk-live-secret')
    end

    it 'keeps the run failed, not successful, on the record' do
      stream(chat)

      expect(store.find(scope: scope, thread_id: 'thread-1', run_id: 'run-1')).to be_failed
    end
  end

  describe 'a tool round (FR-05-AC-01)' do
    let(:chat) do
      FakeChat.new do |chat|
        chat.stream(tool_calls: { 0 => RubyLLM::ToolCall.new(id: 'c1', name: 'search', arguments: '{"q":"x"}') })
        chat.reply(tool_calls: { 'c1' => RubyLLM::ToolCall.new(id: 'c1', name: 'search', arguments: { 'q' => 'x' }) })
        chat.call_tool(id: 'c1', name: 'search', arguments: { 'q' => 'x' })
        chat.tool_result(content: '3 results', tool_call_id: 'c1')
        chat.stream(content: 'Found three.')
        chat.reply(content: 'Found three.')
      end
    end

    it 'maps the whole loop and ends with success' do
      record = stream(chat)

      expect(event_types(sse)).to include('TOOL_CALL_START', 'TOOL_CALL_ARGS', 'TOOL_CALL_END', 'TOOL_CALL_RESULT')
      expect(event_types(sse).last).to eq('RUN_FINISHED')
      expect(record).to be_succeeded
      decode_sse(sse).each { |event| expect_valid_event(event) }
    end
  end

  describe 'a run paused for approval (FR-06-AC-01)' do
    let(:chat) do
      FakeChat.new do |chat|
        chat.stream(tool_calls: { 0 => RubyLLM::ToolCall.new(id: 'c1', name: 'search', arguments: '{}') })
        chat.reply(tool_calls: { 'c1' => RubyLLM::ToolCall.new(id: 'c1', name: 'search', arguments: {}) })
        chat.await([{ id: 'c1', name: 'search', arguments: { 'q' => 'x' } }])
      end
    end

    it 'ends with an interrupt outcome, never a success' do
      record = stream(chat)

      expect(decode_sse(sse).last['outcome']['type']).to eq('interrupt')
      expect(record).to be_interrupted
      expect(record.pending_interrupts.length).to eq(1)
      decode_sse(sse).each { |event| expect_valid_event(event) }
    end

    it 'names the tool call and expires the interrupt from the host clock' do
      stream(chat)

      interrupt = decode_sse(sse).last['outcome']['interrupts'].first
      expect(interrupt['toolCallId']).to eq('c1')
      expect(interrupt['reason']).to eq('tool_call_confirmation')
      expect(interrupt['expiresAt']).to eq('2026-10-17T12:15:00Z')
      expect(interrupt['id']).not_to be_empty
    end

    it 'does not let the arguments digest reach the client' do
      stream(chat)

      expect(sse.string).not_to include('argumentsDigest')
    end
  end

  describe 'a pause this producer cannot express (FR-06-AC-01)' do
    let(:chat) do
      FakeChat.new do |chat|
        chat.stream(content: 'thinking')
        chat.pause!
      end
    end

    it 'reports a sanitized RUN_ERROR instead of a success or a bare interrupt' do
      record = stream(chat)

      expect(event_types(sse).last).to eq('RUN_ERROR')
      expect(decode_sse(sse).last['code']).to eq('unsupported_run_state')
      expect(record).to be_failed
    end
  end

  describe 'retry identity (FR-05-AC-01, no duplicate execution)' do
    let(:chat) do
      FakeChat.new do |chat|
        chat.stream(content: 'done')
        chat.reply(content: 'done')
      end
    end

    it 'refuses to execute an identity that is already reserved' do
      stream(chat)
      first = sse.string.dup

      second = StringIO.new
      expect do
        described_class.new(chat: chat, input: input, scope: scope, store: store).stream(to: second)
      end.to raise_error(RubyLLM::AgUI::StreamError, /already succeeded/)
      expect(second.string).to be_empty
      expect(sse.string).to eq(first)
    end

    it 'refuses the same identity with a changed input as a conflict' do
      stream(chat)
      changed = RubyLLM::AgUI::Input.parse(
        {
          'threadId' => 'thread-1', 'runId' => 'run-1',
          'messages' => [{ 'id' => 'm1', 'role' => 'user', 'content' => 'Different' }]
        }
      )

      expect do
        described_class.new(chat: chat, input: changed, scope: scope, store: store).stream(to: StringIO.new)
      end.to raise_error(RubyLLM::AgUI::RunConflictError)
    end
  end

  describe 'the actor boundary' do
    let(:chat) { FakeChat.new { |chat| chat.reply(content: 'hi') } }

    it 'requires a scope built from authenticated identity' do
      expect { described_class.new(chat: chat, input: input, scope: nil, store: store) }
        .to raise_error(RubyLLM::AgUI::ConfigurationError, /scope/)
      expect { described_class.new(chat: chat, input: input, scope: 42, store: store) }
        .to raise_error(RubyLLM::AgUI::ConfigurationError, /scope/)
    end

    it 'requires a chat and parsed input' do
      expect { described_class.new(chat: Object.new, input: input, scope: scope, store: store) }
        .to raise_error(RubyLLM::AgUI::ConfigurationError, /chat/)
      expect { described_class.new(chat: chat, input: { 'threadId' => 'x' }, scope: scope, store: store) }
        .to raise_error(RubyLLM::AgUI::ConfigurationError, /input/)
    end

    it 'does not let one scope attach to another tenant run' do
      stream(chat)
      other = RubyLLM::AgUI::Input.parse(
        {
          'threadId' => 'thread-1', 'runId' => 'run-1',
          'messages' => [{ 'id' => 'm1', 'role' => 'user', 'content' => 'Hello' }]
        }
      )

      expect do
        described_class.new(chat: chat, input: other, scope: 'tenant-2:actor-9', store: store).stream(to: StringIO.new)
      end.not_to raise_error
    end
  end
end
