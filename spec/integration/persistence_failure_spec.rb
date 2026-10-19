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
end
