# frozen_string_literal: true

RSpec.describe RubyLLM::AgUI::Run do
  # A plain method, not a `let`: the example group already needs several
  # memoized helpers and this value never varies.
  def scope
    'tenant-1:actor-1'
  end

  # A clock the specs move, so an interrupt's expiry is testable.
  def clock
    -> { now }
  end

  def now
    @now ||= Time.utc(2026, 10, 17, 12, 0, 0)
  end

  def advance(seconds)
    @now = now + seconds
  end

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

  describe 'resuming an interrupted run (FR-06-AC-01)' do
    def paused_run
      stream(interrupting_chat)
      store.latest_interrupted(scope: scope, thread_id: 'thread-1')
    end

    def interrupting_chat
      FakeChat.new do |chat|
        chat.stream(tool_calls: { 0 => RubyLLM::ToolCall.new(id: 'c1', name: 'search', arguments: '{}') })
        chat.reply(tool_calls: { 'c1' => RubyLLM::ToolCall.new(id: 'c1', name: 'search', arguments: {}) })
        chat.await([{ id: 'c1', name: 'search', arguments: { 'q' => 'x' } }])
      end
    end

    def resuming_chat(arguments: { 'q' => 'x' })
      FakeChat.new(approvals: [{ id: 'c1', name: 'search', arguments: arguments }]) do |chat|
        chat.call_tool(id: 'c1', name: 'search', arguments: arguments)
        chat.tool_result(content: '3 results', tool_call_id: 'c1')
        chat.stream(content: 'Found three.')
        chat.reply(content: 'Found three.')
      end
    end

    def resume(chat, interrupt_id, status: 'resolved', run_id: 'run-2')
      body = {
        'threadId' => 'thread-1', 'runId' => run_id,
        'messages' => [{ 'id' => 'm1', 'role' => 'user', 'content' => 'Hello' }],
        'resume' => [{ 'interruptId' => interrupt_id, 'status' => status }]
      }
      target = StringIO.new
      described_class.new(
        chat: chat, input: RubyLLM::AgUI::Input.parse(body), scope: scope, store: store,
        redact: RubyLLM::AgUI::Redaction.method(:none), clock: clock
      ).stream(to: target)
      target
    end

    it 'approves the pending tool call and finishes the resumed run' do
      interrupt = paused_run.pending_interrupts.first
      chat = resuming_chat
      target = resume(chat, interrupt.id)

      expect(chat.decisions).to eq('c1' => :approved)
      expect(event_types(target)).to include('TOOL_CALL_RESULT')
      expect(event_types(target).last).to eq('RUN_FINISHED')
      expect(decode_sse(target).last['outcome']).to eq('type' => 'success')
    end

    it 'executes an approved tool once' do
      interrupt = paused_run.pending_interrupts.first
      target = resume(resuming_chat, interrupt.id)

      expect(event_types(target).count('TOOL_CALL_RESULT')).to eq(1)
      decode_sse(target).each { |event| expect_valid_event(event) }
    end

    it 'denies the call when the client cancels the interrupt' do
      interrupt = paused_run.pending_interrupts.first
      chat = resuming_chat

      resume(chat, interrupt.id, status: 'cancelled')

      expect(chat.decisions).to eq('c1' => :denied)
    end

    it 'records the decision on the interrupted run, which stays interrupted' do
      record = paused_run
      resume(resuming_chat, record.pending_interrupts.first.id)

      reloaded = store.latest_interrupted(scope: scope, thread_id: 'thread-1')
      expect(reloaded.run_id).to eq(record.run_id)
      expect(reloaded).to be_interrupted
      expect(reloaded.awaiting_approval?).to be(false)
      expect(reloaded.pending_interrupts).to be_empty
    end

    it 'refuses an unknown interrupt before the run is reserved or opened' do
      paused_run

      expect { resume(resuming_chat, 'int-unknown') }
        .to raise_error(RubyLLM::AgUI::ResumeRejectedError, /latest run's/)
      expect(store.find(scope: scope, thread_id: 'thread-1', run_id: 'run-2')).to be_nil
    end

    it 'refuses a resume whose tool call arguments changed since the interrupt' do
      interrupt = paused_run.pending_interrupts.first

      expect { resume(resuming_chat(arguments: { 'q' => 'y' }), interrupt.id) }
        .to raise_error(RubyLLM::AgUI::ResumeRejectedError, /changed/)
    end

    it 'refuses a tool call that is not pending on the host chat' do
      interrupt = paused_run.pending_interrupts.first
      chat = FakeChat.new { |fake| fake.reply(content: 'nothing pending') }

      expect { resume(chat, interrupt.id) }
        .to raise_error(RubyLLM::AgUI::ResumeRejectedError, /not pending/)
    end

    it 'refuses an expired interrupt' do
      interrupt = paused_run.pending_interrupts.first
      advance(901)

      expect { resume(resuming_chat, interrupt.id) }
        .to raise_error(RubyLLM::AgUI::ResumeRejectedError, /expired/)
    end

    it 'reconnects the exact completed resume without applying its decision again' do
      interrupt = paused_run.pending_interrupts.first
      resume(resuming_chat, interrupt.id)
      chat = resuming_chat
      target = resume(chat, interrupt.id)
      expect(event_types(target)).to eq(%w[RUN_STARTED STATE_SNAPSHOT RUN_FINISHED])
      expect(decode_sse(target).last['outcome']).to eq('type' => 'success')
      expect(chat.decisions).to be_empty
    end

    it 'refuses changed input under a completed resume identity' do
      interrupt = paused_run.pending_interrupts.first
      resume(resuming_chat, interrupt.id)
      expect { resume(resuming_chat, interrupt.id, status: 'cancelled') }
        .to raise_error(RubyLLM::AgUI::RunConflictError)
    end

    it 'refuses a decision another resume already recorded, without executing the tool' do
      interrupt = paused_run.pending_interrupts.first
      resume(resuming_chat, interrupt.id)

      chat = resuming_chat
      expect { resume(chat, interrupt.id, run_id: 'run-3') }
        .to raise_error(RubyLLM::AgUI::ResumeRejectedError, /already been answered/)
      expect(chat.decisions).to be_empty
    end
  end

  describe 'a changed input under an already-reserved identity (FR-05-AC-01)' do
    let(:chat) do
      FakeChat.new do |chat|
        chat.stream(content: 'done')
        chat.reply(content: 'done')
      end
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

  describe 'reconnecting to a run that ended (FR-05-AC-01)' do
    # A chat that must never be driven: a reconnect reports an outcome, it does
    # not execute the turn again.
    def unrunnable
      @unrunnable ||= FakeChat.new { |_chat| raise 'a reconnect must not drive the chat' }
    end

    def reconnect(target = StringIO.new)
      described_class.new(
        chat: unrunnable, input: input, scope: scope, store: store,
        redact: RubyLLM::AgUI::Redaction.method(:none), clock: clock
      ).stream(to: target)
    end

    def succeeding_chat
      FakeChat.new do |chat|
        chat.stream(content: 'Hello')
        chat.reply(content: 'Hello')
      end
    end

    it 'serves the recorded outcome and a state snapshot instead of the deltas' do
      stream(succeeding_chat)
      recorded = sse.string.dup

      target = StringIO.new
      record = reconnect(target)

      expect(record).to be_succeeded
      expect(event_types(target)).to eq(%w[RUN_STARTED STATE_SNAPSHOT RUN_FINISHED])
      expect(decode_sse(target).last['outcome']).to eq('type' => 'success')
      expect(sse.string).to eq(recorded)
    end

    it 'writes only schema-valid events on a reconnect' do
      stream(succeeding_chat)

      target = StringIO.new
      reconnect(target)

      decode_sse(target).each { |event| expect_valid_event(event) }
    end

    it 'reports a cancelled run as cancelled' do
      stream(
        FakeChat.new do |chat|
          chat.stream(content: 'half a th')
          chat.cancel!
        end
      )

      target = StringIO.new
      reconnect(target)

      expect(decode_sse(target).last['outcome']).to eq('type' => 'cancelled')
    end

    it 'reports the recorded failure without the exception text' do
      stream(FakeChat.new { |chat| chat.fail!(RubyLLM::RateLimitError.new('key sk-live-secret leaked')) })

      target = StringIO.new
      reconnect(target)

      error = decode_sse(target).last
      expect(error['type']).to eq('RUN_ERROR')
      expect(error['code']).to eq('provider_rate_limited')
      expect(target.string).not_to include('sk-live-secret')
    end

    it 'reports the interrupt a paused run still waits for' do
      stream(
        FakeChat.new do |chat|
          chat.stream(tool_calls: { 0 => RubyLLM::ToolCall.new(id: 'c1', name: 'search', arguments: '{}') })
          chat.reply(tool_calls: { 'c1' => RubyLLM::ToolCall.new(id: 'c1', name: 'search', arguments: {}) })
          chat.await([{ id: 'c1', name: 'search', arguments: { 'q' => 'x' } }])
        end
      )
      interrupt = store.latest_interrupted(scope: scope, thread_id: 'thread-1').pending_interrupts.first

      target = StringIO.new
      reconnect(target)

      outcome = decode_sse(target).last['outcome']
      expect(outcome['type']).to eq('interrupt')
      expect(outcome['interrupts'].map { |entry| entry['id'] }).to eq([interrupt.id])
    end

    it 'publishes the state the host gave the run, not the client input' do
      described_class.new(
        chat: succeeding_chat, input: input, scope: scope, store: store, state: { 'step' => 3 }
      ).stream(to: StringIO.new)

      target = StringIO.new
      reconnect(target)

      expect(decode_sse(target)[1]['snapshot']).to eq('step' => 3)
    end

    it 'refuses to attach a second stream to a run that has not ended' do
      record = store.reserve(scope: scope, thread_id: 'thread-1', run_id: 'run-1', digest: input.digest).record
      store.save(record.start(now: now))

      expect { reconnect }
        .to raise_error(RubyLLM::AgUI::StreamError, /still started/)
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

  describe 'a second turn on the same chat (FR-05-AC-01)' do
    # RubyLLM's callbacks are additive: the callbacks the first run registered
    # are still attached when that chat completes a second time, which is the
    # normal shape of a conversation.
    let(:chat) do
      FakeChat.new do |fake|
        fake.stream(content: 'Hello')
        fake.reply(content: 'Hello')
      end
    end

    def input_for(run_id)
      RubyLLM::AgUI::Input.parse(
        {
          'threadId' => 'thread-1', 'runId' => run_id,
          'messages' => [{ 'id' => 'm1', 'role' => 'user', 'content' => 'Hello' }]
        }
      )
    end

    def stream_turn(run_id, to:)
      described_class.new(
        chat: chat, input: input_for(run_id), scope: scope, store: store,
        redact: RubyLLM::AgUI::Redaction.method(:none), clock: clock
      ).stream(to: to)
    end

    it 'writes nothing more to the first run stream' do
      first = StringIO.new
      stream_turn('run-1', to: first)
      finished = first.string

      stream_turn('run-2', to: StringIO.new)

      expect(first.string).to eq(finished)
    end

    it 'streams the second run as its own run, with its own ids' do
      stream_turn('run-1', to: StringIO.new)

      second = StringIO.new
      record = stream_turn('run-2', to: second)

      expect(record).to be_succeeded
      expect(event_types(second)).to eq(
        %w[RUN_STARTED STEP_STARTED TEXT_MESSAGE_START TEXT_MESSAGE_CONTENT TEXT_MESSAGE_END STEP_FINISHED
           RUN_FINISHED]
      )
      expect(record.sequence).to eq(7)
      expect(decode_sse(second).filter_map { |event| event['messageId'] }).to all(include('run-2'))
    end
  end

  describe 'opt-in tool progress' do
    def progressing_chat
      FakeChat.new do |chat|
        call = RubyLLM::ToolCall.new(id: 'p1', name: 'search', arguments: {})
        chat.call_tool(id: call.id, name: call.name, arguments: {})
        chat.progress(call, message: 'fixture-secret')
        chat.tool_result(content: 'done', tool_call_id: call.id)
      end
    end

    def progress_run(chat, **options)
      described_class.new(chat: chat, input: input, scope: scope, store: store, **options).stream(to: sse)
    end

    it 'does not publish progress by default' do
      expect(progress_run(progressing_chat)).to be_succeeded
      expect(event_types(sse)).not_to include('ACTIVITY_SNAPSHOT')
    end

    it 'uses global opt-in and redacts progress by default' do
      RubyLLM::AgUI.config.emit_tool_progress = true
      expect(progress_run(progressing_chat)).to be_succeeded
      expect(event_types(sse)).to include('ACTIVITY_SNAPSHOT')
      expect(sse.string).not_to include('fixture-secret')
      decode_sse(sse).each { |event| expect_valid_event(event) }
    end

    it 'lets a run disable globally enabled progress' do
      RubyLLM::AgUI.config.emit_tool_progress = true
      progress_run(progressing_chat, emit_tool_progress: false)
      expect(event_types(sse)).not_to include('ACTIVITY_SNAPSHOT')
    end

    it 'finishes atomically with respect to a late progress callback' do
      entered = Queue.new
      release = Queue.new
      allow(store).to receive(:save).and_wrap_original do |save, record|
        saved = save.call(record)
        if record.terminal?
          entered << true
          release.pop
        end
        saved
      end
      chat = progressing_chat
      runner = Thread.new { progress_run(chat, emit_tool_progress: true) }
      entered.pop
      call = RubyLLM::ToolCall.new(id: 'late', name: 'search', arguments: {})
      late = Thread.new { chat.progress(call, message: 'after decision') }
      expect(late.join(0.05)).to be_nil
      release << true
      runner.value
      late.value
      expect(event_types(sse).count('ACTIVITY_SNAPSHOT')).to eq(1)
      expect(event_types(sse).last).to eq('RUN_FINISHED')
    ensure
      release << true
      runner&.join
      late&.join
    end

    it 'serializes concurrent progress and ignores callbacks after the terminal event' do
      callbacks = Queue.new
      chat = FakeChat.new do |fake|
        threads = 8.times.map do |index|
          Thread.new do
            call = RubyLLM::ToolCall.new(id: "p#{index}", name: 'search', arguments: {})
            fake.call_tool(id: call.id, name: call.name, arguments: {})
            fake.progress(call, value: 1, total: 2)
            callbacks << call
          end
        end
        threads.each(&:value)
      end
      record = progress_run(chat, emit_tool_progress: true)
      finished = sse.string.dup
      8.times { chat.progress(callbacks.pop, message: 'after terminal') }
      expect(record).to be_succeeded
      expect(sse.string).to eq(finished)
      expect(event_types(sse).count('ACTIVITY_SNAPSHOT')).to eq(8)
      expect(event_types(sse).last).to eq('RUN_FINISHED')
      expect(event_types(sse).count('RUN_FINISHED')).to eq(1)
      decode_sse(sse).each { |event| expect_valid_event(event) }
    end
  end
end
