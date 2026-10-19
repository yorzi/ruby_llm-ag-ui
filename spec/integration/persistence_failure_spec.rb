# frozen_string_literal: true

RSpec.describe 'Uncertain persistence' do
  let(:store) { RubyLLM::AgUI::Store::MemoryStore.new }
  let(:input) { RubyLLM::AgUI::Input.parse({ 'threadId' => 't', 'runId' => 'r', 'messages' => [] }) }

  def run(chat = FakeChat.new { |fake| fake.reply(content: 'done') }, to: StringIO.new)
    RubyLLM::AgUI::Run.new(chat: chat, input: input, scope: 'actor:1', store: store).stream(to: to)
  end

  it 'does not guess a failure after a terminal write committed but its acknowledgement was lost' do
    allow(store).to receive(:save).and_wrap_original do |save, record|
      result = save.call(record)
      raise IOError, 'private database detail' if record.succeeded?

      result
    end
    expect { run }.to raise_error(RubyLLM::AgUI::PersistenceError)
    output = StringIO.new
    expect(run(FakeChat.new { raise 'must not execute again' }, to: output)).to be_succeeded
    expect(decode_sse(output).last['outcome']).to eq('type' => 'success')
  end

  it 'leaves an uncommitted terminal write non-terminal without a speculative second write' do
    statuses = []
    allow(store).to receive(:save).and_wrap_original do |save, record|
      statuses << record.status
      raise IOError, 'private database detail' if record.terminal?

      save.call(record)
    end
    expect { run }.to raise_error(RubyLLM::AgUI::PersistenceError) do |error|
      expect(error.message).not_to include('private')
    end
    expect(statuses).to eq(%i[started succeeded])
    expect(store.find(scope: 'actor:1', thread_id: 't', run_id: 'r')).to be_started
  end

  it 'reports an uncertain reservation without making a provider turn' do
    allow(store).to receive(:reserve).and_wrap_original do |reserve, **identity|
      reserve.call(**identity)
      raise IOError, 'private database detail'
    end
    executed = false
    expect { run(FakeChat.new { executed = true }) }.to raise_error(RubyLLM::AgUI::PersistenceError)
    expect(executed).to be(false)
    expect(store.find(scope: 'actor:1', thread_id: 't', run_id: 'r')).to be_reserved
  end

  it 'keeps an uncertain approval decision non-terminal without executing its tool' do
    source = store.reserve(scope: 'actor:1', thread_id: 't', run_id: 'source', digest: 'source').record
    interrupt = RubyLLM::AgUI::Interrupt.new(id: 'i', tool_call_id: 'c', arguments_digest: RubyLLM::AgUI::Canonical.digest({}),
                                             expires_at: Time.now + 900, created_at: Time.now)
    store.save(source.interrupted([interrupt], now: Time.now))
    allow(store).to receive(:redeem_interrupt).and_wrap_original do |redeem, **decision|
      redeem.call(**decision)
      raise IOError, 'private database detail'
    end
    resumed_input = RubyLLM::AgUI::Input.parse({ 'threadId' => 't', 'runId' => 'resume', 'messages' => [],
                                                 'resume' => [{ 'interruptId' => 'i', 'status' => 'resolved' }] })
    chat = FakeChat.new(approvals: [{ id: 'c', name: 'fixture', arguments: {} }]) { raise 'must not execute' }
    resumed = RubyLLM::AgUI::Run.new(chat: chat, input: resumed_input, scope: 'actor:1', store: store)

    expect { resumed.stream(to: StringIO.new) }.to raise_error(RubyLLM::AgUI::PersistenceError)
    expect(chat.decisions).to be_empty
    expect(store.find(scope: 'actor:1', thread_id: 't', run_id: 'resume')).to be_started
    expect(store.find_interrupt(scope: 'actor:1', thread_id: 't', interrupt_id: 'i')).to be_approved
  end
end
