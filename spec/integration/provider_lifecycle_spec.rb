# frozen_string_literal: true

RSpec.describe 'RubyLLM lifecycle with intercepted HTTP' do
  let(:store) { RubyLLM::AgUI::Store::MemoryStore.new }
  let(:input) { RubyLLM::AgUI::Input.parse({ 'threadId' => 't', 'runId' => 'r', 'messages' => [] }) }
  let(:chat) do
    configuration = RubyLLM::Configuration.new
    configuration.openai_api_key = 'offline-fixture'
    configuration.max_retries = 0
    RubyLLM::Context.new(configuration).chat(model: 'fixture-model', provider: :openai,
                                             assume_model_exists: true).tap do |instance|
      instance.add_message(role: :user, content: 'fixture')
    end
  end

  def run(to:)
    RubyLLM::AgUI::Run.new(chat: chat, input: input, scope: 'actor:1', store: store).stream(to: to)
  end

  it 'maps an actual RubyLLM HTTP timeout to a sanitized, reconnectable timeout failure' do
    stub_request(:post, 'https://api.openai.com/v1/responses').to_raise(Faraday::TimeoutError.new('private detail'))
    output = StringIO.new

    expect(run(to: output)).to be_failed
    expect(decode_sse(output).last).to include('type' => 'RUN_ERROR', 'code' => 'transport_timeout')
    expect(output.string).not_to include('private')
    replay = StringIO.new
    expect(run(to: replay)).to be_failed
    expect(decode_sse(replay).last).to eq(decode_sse(output).last)
    expect(WebMock).to have_requested(:post, 'https://api.openai.com/v1/responses').once
  end

  it 'honors Chat#cancel at its next checkpoint before sending a provider request' do
    chat.cancel
    output = StringIO.new

    expect(run(to: output)).to be_cancelled
    expect(decode_sse(output).last['outcome']).to eq('type' => 'cancelled')
    expect(chat).not_to be_cancelled
    expect(WebMock).not_to have_requested(:post, 'https://api.openai.com/v1/responses')
  end
end
