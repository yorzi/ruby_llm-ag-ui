# frozen_string_literal: true

RSpec.shared_examples 'versioned run storage' do
  def reserve_record
    store.reserve(scope: 'actor:1', thread_id: 't', run_id: 'r', digest: 'd').record
  end

  def stored_record
    store.find(scope: 'actor:1', thread_id: 't', run_id: 'r')
  end

  it 'rejects an old worker snapshot after another writer finishes' do
    old = store.save(reserve_record.start(now: Time.now))
    store.save(old.finish(:cancelled, now: Time.now))

    expect { store.save(old.finish(:succeeded, now: Time.now)) }
      .to raise_error(RubyLLM::AgUI::RunConflictError)
    expect(stored_record).to be_cancelled
  end

  it 'requires callers to retain the new record returned by save' do
    old = reserve_record
    current = store.save(old.start(now: Time.now))

    expect(current.revision).to eq(old.revision + 1)
    expect { store.save(old.start(now: Time.now)) }.to raise_error(RubyLLM::AgUI::RunConflictError)
  end

  it 'recovers an observed non-terminal run without releasing its identity' do
    old = store.save(reserve_record.start(now: Time.now))
    recovered = store.recover(old)

    expect(recovered).to be_failed
    expect(recovered.failure).to include('code' => 'worker_lost')
    expect(store.reserve(scope: 'actor:1', thread_id: 't', run_id: 'r', digest: 'd')).to be_attached
    expect { store.save(old.finish(:succeeded, now: Time.now)) }
      .to raise_error(RubyLLM::AgUI::RunConflictError)
    expect(stored_record.failure).to eq(recovered.failure)
  end

  it 'does not recover a run that advanced since the host inspected it' do
    old = reserve_record
    store.save(old.start(now: Time.now))

    expect { store.recover(old) }.to raise_error(RubyLLM::AgUI::RunConflictError)
    expect(stored_record).to be_started
  end

  it 'does not replace a completed outcome with worker loss' do
    completed = store.save(reserve_record.finish(:succeeded, now: Time.now))

    expect { store.recover(completed) }.to raise_error(RubyLLM::AgUI::RunConflictError)
    expect(stored_record).to be_succeeded
  end

  it 'loads pre-0.3 JSON records without a revision field' do
    legacy = reserve_record.to_storage.except('revision')
    restored = RubyLLM::AgUI::RunRecord.from_storage(legacy)

    expect(restored.revision).to eq(0)
    expect(store.save(restored.start(now: Time.now))).to be_started
  end

  it 'disables callbacks even when a stale producer cannot save its outcome' do
    turns = 0
    storage = store
    first_input = RubyLLM::AgUI::Input.parse({ 'threadId' => 't', 'runId' => 'r', 'messages' => [] })
    chat = FakeChat.new do |fake|
      turns += 1
      fake.stream(content: 'hello')
      fake.call_tool(id: "c#{turns}", name: 'fixture', arguments: {})
      storage.recover(storage.find(scope: 'actor:1', thread_id: 't', run_id: 'r')) if turns == 1
    end
    output = StringIO.new
    first = RubyLLM::AgUI::Run.new(chat: chat, input: first_input, scope: 'actor:1', store: store)
    expect { first.stream(to: output) }.to raise_error(RubyLLM::AgUI::RunConflictError)
    prefix = output.string.dup
    second_input = RubyLLM::AgUI::Input.parse({ 'threadId' => 't', 'runId' => 'r2', 'messages' => [] })

    RubyLLM::AgUI::Run.new(chat: chat, input: second_input, scope: 'actor:1', store: store).stream(to: StringIO.new)

    expect(output.string).to eq(prefix)
    expect(stored_record.failure).to include('code' => 'worker_lost')
  end
end
