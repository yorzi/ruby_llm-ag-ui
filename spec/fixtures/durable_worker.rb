# frozen_string_literal: true

# Independent Ruby process with its own SQLite connection. Input is synthetic.
require 'bundler/setup'
require 'ruby_llm/ag_ui'
require 'active_record'
require 'erb'
require 'stringio'
require 'ruby_llm/ag_ui/rails/active_record_store'

request = JSON.parse($stdin.gets)
ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: request.fetch('database'), timeout: 10_000)
ActiveRecord::Base.logger = nil
store = RubyLLM::AgUI::Rails::ActiveRecordStore.new
identity = { scope: 'actor:1', thread_id: 't', run_id: 'r' }
input = RubyLLM::AgUI::Input.parse({ 'threadId' => 't', 'runId' => 'r', 'messages' => [] })
operation = request.fetch('operation')

if operation == 'prepare'
  template = File.expand_path('../../lib/generators/ruby_llm/ag_ui/templates/create_ruby_llm_ag_ui_runs.rb.tt', __dir__)
  Object.class_eval(ERB.new(File.read(template)).result, template)
  ActiveRecord::Migration.verbose = false
  CreateRubyLlmAgUiRuns.new.migrate(:up)
  if request['seed']
    record = store.reserve(**identity, digest: input.digest).record.start(now: Time.now)
    if request['seed'] == 'interrupt'
      interrupt = RubyLLM::AgUI::Interrupt.new(id: 'i', tool_call_id: 'c', arguments_digest: 'd',
                                               created_at: Time.now, expires_at: Time.now + 3600)
      record = record.interrupted([interrupt], now: Time.now)
    end
    store.save(record)
  end
  $stdout.puts 'PREPARED'
  exit
end

observed = store.find(**identity)
$stdout.puts 'READY'
$stdout.flush
raise 'missing barrier' unless $stdin.gets&.strip == 'GO'

if request['write_barrier']
  RubyLLM::AgUI::Rails::Record.prepend(Module.new do
    def write_run_record(record)
      $stdout.puts 'WRITE_READY'
      $stdout.flush
      raise 'missing write barrier' unless $stdin.gets&.strip == 'COMMIT'

      super
    end
  end)
end

begin
  result = case operation
           when 'reserve'
             reservation = store.reserve(**identity, digest: request.fetch('digest', input.digest))
             { result: reservation.status.to_s }
           when 'redeem'
             redemption = store.redeem_interrupt(scope: 'actor:1', thread_id: 't', interrupt_id: 'i',
                                                 decision: request.fetch('decision', 'approved').to_sym, now: Time.now)
             { result: redemption.recorded? ? 'recorded' : 'replayed', decision: redemption.interrupt.status.to_s }
           when 'finish'
             { result: store.save(observed.finish(:succeeded, now: Time.now)).status.to_s }
           when 'recover'
             { result: store.recover(observed).status.to_s }
           when 'run'
             require_relative '../support/fake_chat'
             chat = FakeChat.new do |fake|
               fake.call_tool(id: 'c', name: 'fixture', arguments: {})
               File.open(request.fetch('effects'), 'a') { |file| file.puts('effect') }
               $stdout.puts 'TOOL_EFFECT_DONE'
               $stdout.flush
               $stdin.gets
               fake.tool_result(content: 'done', tool_call_id: 'c')
             end
             run = RubyLLM::AgUI::Run.new(chat: chat, input: input, scope: 'actor:1', store: store)
             { result: run.stream(to: StringIO.new).status.to_s }
           when 'recover_and_reconnect'
             require_relative '../support/fake_chat'
             recovered = store.recover(observed)
             executed = false
             chat = FakeChat.new { executed = true }
             output = StringIO.new
             RubyLLM::AgUI::Run.new(chat: chat, input: input, scope: 'actor:1', store: store).stream(to: output)
             terminal = JSON.parse(output.string.split("\n\n").last.delete_prefix('data: '))
             { result: recovered.status.to_s, code: terminal.fetch('code'), executed: executed,
               attached: store.reserve(**identity, digest: input.digest).attached?,
               isolated: store.find(**identity, scope: 'actor:2').nil? }
           else
             raise 'unknown operation'
           end
  $stdout.puts JSON.generate(result)
rescue StandardError => e
  $stdout.puts JSON.generate(error: e.class.name)
end
