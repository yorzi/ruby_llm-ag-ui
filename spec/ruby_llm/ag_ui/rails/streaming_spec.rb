# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RubyLLM::AgUI::Rails::Streaming do
  def body(run_id: 'run-1', content: 'Hello')
    JSON.generate(
      'threadId' => 'thread-1', 'runId' => run_id,
      'messages' => [{ 'id' => 'm1', 'role' => 'user', 'content' => content }]
    )
  end

  def chat(text: 'Hello')
    FakeChat.new do |fake|
      fake.stream(content: text)
      fake.reply(content: text)
    end
  end

  let(:store) { RubyLLM::AgUI::Store::MemoryStore.new }
  let(:controller) { FakeController.new(body: body) }

  before { RubyLLM::AgUI.configure { |config| config.run_store = store } }

  describe 'the happy path (FR-01)' do
    it 'streams a schema-valid run and returns its record' do
      record = controller.stream_ag_ui_run { |_input| chat }

      expect(record).to be_succeeded
      expect(controller.refusals).to be_empty
      expect(controller.response.headers['Content-Type']).to eq('text/event-stream; charset=utf-8')
      expect(controller.response.headers['Cache-Control']).to eq('no-cache')
      expect(controller.response.headers['X-Accel-Buffering']).to eq('no')

      events = decode_sse(controller.response.stream)
      expect(events.first['type']).to eq('RUN_STARTED')
      expect(events.last['type']).to eq('RUN_FINISHED')
      events.each { |event| expect_valid_event(event) }
    end

    it 'hands the parsed input to the block and drives the chat it returns' do
      seen = nil
      controller.stream_ag_ui_run do |input|
        seen = input
        chat(text: 'From the host chat')
      end

      expect(seen.thread_id).to eq('thread-1')
      expect(controller.response.stream.string).to include('From the host chat')
    end

    it 'reserves the run under the authenticated scope, not one from the body' do
      controller.stream_ag_ui_run { |_input| chat }

      expect(store.find(scope: 'tenant-1:actor-1', thread_id: 'thread-1', run_id: 'run-1')).to be_succeeded
      expect(store.find(scope: 'tenant-2:actor-9', thread_id: 'thread-1', run_id: 'run-1')).to be_nil
    end
  end

  describe 'what it refuses before streaming anything' do
    it 'refuses a client that cannot read an event stream' do
      controller = FakeController.new(accept: 'application/json', body: body)

      controller.stream_ag_ui_run { |_input| raise 'the chat must not be built' }

      code, message = controller.refusals.first
      expect(code).to eq(406)
      expect(message).to include('text/event-stream')
      expect(controller.response.stream.string).to be_empty
      expect(store.latest_run(scope: 'tenant-1:actor-1', thread_id: 'thread-1')).to be_nil
    end

    it 'refuses a body that is not JSON' do
      controller = FakeController.new(body: 'not json')

      controller.stream_ag_ui_run { |_input| chat }

      expect(controller.refusals.first.first).to eq(400)
      expect(controller.response.stream.string).to be_empty
    end

    it 'refuses a JSON body whose text is not UTF-8' do
      controller = FakeController.new(body: %({"threadId":"thread-\xFF","runId":"run-1","messages":[]}).b)

      controller.stream_ag_ui_run { |_input| chat }

      expect(controller.refusals.first.first).to eq(400)
      expect(controller.response.stream.string).to be_empty
    end

    it 'refuses an input the gem will not accept' do
      controller = FakeController.new(body: JSON.generate('threadId' => 'thread-1', 'runId' => 'run-1'))

      controller.stream_ag_ui_run { |_input| chat }

      expect(controller.refusals.first.first).to eq(400)
    end

    it 'refuses a body larger than the configured limit' do
      RubyLLM::AgUI.configure { |config| config.max_input_bytes = 32 }
      controller = FakeController.new(body: body)

      controller.stream_ag_ui_run { |_input| chat }

      code, message = controller.refusals.first
      expect(code).to eq(413)
      expect(message).to include('exceeds 32 bytes')
    end

    it 'refuses the same run id carrying a different input' do
      controller.stream_ag_ui_run { |_input| chat }
      second = FakeController.new(body: body(content: 'Different'))

      second.stream_ag_ui_run { |_input| chat }

      expect(second.refusals.first.first).to eq(409)
      expect(second.response.stream.string).to be_empty
    end

    it 'refuses to run at all when the host never says who the actor is' do
      anonymous = AnonymousController.new(body: body)

      expect { anonymous.stream_ag_ui_run { |_input| chat } }
        .to raise_error(RubyLLM::AgUI::ConfigurationError, /ag_ui_scope/)
      expect(anonymous.response.stream.string).to be_empty
      expect(store.latest_run(scope: 'tenant-1:actor-1', thread_id: 'thread-1')).to be_nil
    end

    it 'needs a block to build the chat' do
      expect { controller.stream_ag_ui_run }.to raise_error(RubyLLM::AgUI::ConfigurationError, /block/)
    end
  end

  describe 'a client that leaves mid-run (FR-05)' do
    it 'continues after the real Rails ClientDisconnected exception' do
      controller = FakeController.new(body: body)
      allow(controller.response.stream).to receive(:write).and_raise(ActionController::Live::ClientDisconnected)

      expect(controller.stream_ag_ui_run { |_input| chat }).to be_succeeded
      expect(controller.refusals).to be_empty
    end

    it 'returns the real stored outcome without a refusal on the truncated stream' do
      controller = FakeController.new(body: body, drops: true)

      expect(controller.stream_ag_ui_run { |_input| chat }).to be_succeeded
      expect(controller.refusals).to be_empty
    end

    it 'still records the run, so a retry attaches instead of executing again' do
      controller = FakeController.new(body: body, drops: true)

      controller.stream_ag_ui_run { |_input| chat }

      expect(store.find(scope: 'tenant-1:actor-1', thread_id: 'thread-1', run_id: 'run-1')).not_to be_nil
    end
  end
end
