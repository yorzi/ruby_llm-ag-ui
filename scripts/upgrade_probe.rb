# frozen_string_literal: true

# Offline harness for bin/verify-upgrade. Each phase runs outside the checkout.
gem 'ruby_llm-ag_ui', ENV.fetch('UPGRADE_VERSION')
require 'rails'
require 'active_record'
require 'action_controller'
require 'rails/generators'
require 'rails/generators/active_record'
require 'ruby_llm/ag_ui'
require 'stringio'
require_relative '../spec/support/fake_chat'

loaded = $LOADED_FEATURES.find { |path| path.end_with?('/ruby_llm/ag_ui.rb') }
abort 'loaded checkout instead of installed artifact' unless
  File.realpath(loaded) == File.join(File.realpath(ENV.fetch('EXPECTED_GEM_ROOT')), 'lib/ruby_llm/ag_ui.rb')

ActiveRecord::Base.logger = nil
ActiveRecord::Base.establish_connection(adapter: 'sqlite3',
                                        database: File.join(ENV.fetch('UPGRADE_HOME'), 'runs.sqlite3'))

# One logical clock makes persisted interrupt expiry deterministic across phases.
module UpgradeProbe
  CALL = { id: 'original-call', name: 'fixture_lookup', arguments: { 'value' => 'fixture' } }.freeze
  NOW = Time.utc(2026, 10, 26).freeze

  module_function

  def store
    @store ||= RubyLLM::AgUI::Rails::ActiveRecordStore.new(clock: -> { NOW })
  end

  def input(thread, run, resume: [])
    RubyLLM::AgUI::Input.parse({ 'threadId' => thread, 'runId' => run, 'messages' => [], 'resume' => resume })
  end

  def stream(chat, input)
    output = StringIO.new
    record = RubyLLM::AgUI::Run.new(chat: chat, input: input, scope: 'actor:upgrade',
                                    store: store, clock: -> { NOW }).stream(to: output)
    events = output.string.lines.filter_map do |line|
      JSON.parse(line.delete_prefix('data: ')) if line.start_with?('data: ')
    end
    [record, events]
  end

  def generate(destination)
    generator = Rails::Generators.find_by_namespace('ruby_llm:ag_ui:install')
    generator.start([], destination_root: destination, quiet: true)
    Dir[File.join(destination, '**/*')].select { |path| File.file?(path) }.to_h do |path|
      [File.basename(path).sub(/\A\d+_/, ''), File.binread(path)]
    end
  end

  def prepare_schema
    destination = File.join(ENV.fetch('UPGRADE_HOME'), 'old-generated')
    File.write('generated.json', JSON.generate(generate(destination)))
    load Dir[File.join(destination, 'db/migrate/*.rb')].fetch(0)
    CreateRubyLlmAgUiRuns.new.suppress_messages { CreateRubyLlmAgUiRuns.new.migrate(:up) }
  end

  def seed_interrupt(thread)
    chat = FakeChat.new do |fake|
      fake.call_tool(**CALL)
      fake.await([CALL])
    end
    record, = stream(chat, input(thread, 'old'))
    abort 'baseline did not interrupt' unless record.interrupted?
  end

  def seed
    prepare_schema
    chat = FakeChat.new { |fake| fake.stream(content: 'old result') }
    record, = stream(chat, input('completed', 'old'))
    abort 'baseline did not succeed' unless record.succeeded?
    %w[approve deny].each { |thread| seed_interrupt(thread) }
    puts 'UPGRADE_BASELINE_PASS: generated schema, succeeded run, two persisted interrupts'
  end

  def reconnect
    chat = FakeChat.new { raise 'reconnect executed a provider turn' }
    record, events = stream(chat, input('completed', 'old'))
    abort 'completed outcome changed' unless record.succeeded?
    assert_replay(events)
    abort 'scope crossed' if store.find(scope: 'actor:other', thread_id: 'completed', run_id: 'old')
  end

  def assert_replay(events)
    abort 'reconnect repeated content' unless events.map { |event| event['type'] } ==
                                              %w[RUN_STARTED STATE_SNAPSHOT RUN_FINISHED]
  end

  def resume_request(thread, status)
    source = store.latest_interrupted(scope: 'actor:upgrade', thread_id: thread)
    input(thread, 'new', resume: [{ 'interruptId' => source.pending_interrupts.first.id, 'status' => status }])
  end

  def resumed_chat(effects)
    FakeChat.new(approvals: [CALL]) do |fake|
      fake.call_tool(**CALL)
      effects << 'synthetic effect' if fake.decisions[CALL[:id]] == :approved
      fake.tool_result(content: 'fixture', tool_call_id: CALL[:id])
    end
  end

  def assert_result(events)
    abort 'original call repeated' if events.any? { |event| event['type'] == 'TOOL_CALL_START' }
    result = events.select { |event| event['type'] == 'TOOL_CALL_RESULT' }
    abort 'result association lost' unless result.size == 1 && result.first['toolCallId'] == CALL[:id]
  end

  def resume(thread, status)
    request = resume_request(thread, status)
    effects = []
    chat = resumed_chat(effects)
    record, events = stream(chat, request)
    abort 'resume did not succeed' unless record.succeeded?

    assert_result(events)
    assert_replay(stream(chat, request).last)
    abort 'wrong effect count' unless effects.size == (status == 'resolved' ? 1 : 0)
  end

  def verify
    abort 'generated files changed' unless generate('new-generated') == JSON.parse(File.read('generated.json'))
    reconnect
    resume('approve', 'resolved')
    resume('deny', 'cancelled')
    puts 'UPGRADE_CANDIDATE_PASS: unchanged generator, reconnect, approval once, denial, scope isolation'
  end
end

ENV.fetch('UPGRADE_PHASE') == '0' ? UpgradeProbe.seed : UpgradeProbe.verify
