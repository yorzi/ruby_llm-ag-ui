# frozen_string_literal: true

RSpec.describe 'Independent SQLite workers' do
  include DurableWorkers

  it 'reserves one identity once across two independent Ruby processes' do
    results = compete(requests: [{ operation: 'reserve' }, { operation: 'reserve' }])

    expect(results.map { |entry| entry['result'] }).to contain_exactly('created', 'attached')
  end

  it 'rejects changed input racing for the same identity' do
    results = compete(requests: [{ operation: 'reserve', digest: 'a' }, { operation: 'reserve', digest: 'b' }])

    expect(results).to include({ 'result' => 'created' }, { 'error' => 'RubyLLM::AgUI::RunConflictError' })
  end

  it 'redeems one approval once across competing workers' do
    results = compete(seed: 'interrupt', requests: [{ operation: 'redeem' }, { operation: 'redeem' }])

    expect(results.map { |entry| entry['result'] }).to contain_exactly('recorded', 'replayed')
    expect(results.map { |entry| entry['decision'] }).to all(eq('approved'))
  end

  it 'never changes the winning approval decision' do
    results = compete(seed: 'interrupt', requests: [{ operation: 'redeem', decision: 'approved' },
                                                    { operation: 'redeem', decision: 'cancelled' }])

    expect(results.count { |entry| entry['result'] == 'recorded' }).to eq(1)
    expect(results).to include('error' => 'RubyLLM::AgUI::ResumeRejectedError')
  end

  it 'allows only one of two writes made from the same observed revision' do
    results = compete(seed: 'started', requests: [{ operation: 'finish' }, { operation: 'finish' }])

    expect(results.count { |entry| entry['result'] == 'succeeded' }).to eq(1)
    expect(results).to include('error' => 'RubyLLM::AgUI::StaleRecordError')
  end

  it 'never lets recovery overwrite a competing completion' do
    results = compete(seed: 'started', requests: [{ operation: 'finish' }, { operation: 'recover' }])

    expect(results.count { |entry| %w[succeeded failed].include?(entry['result']) }).to eq(1)
    expect(results).to include('error' => 'RubyLLM::AgUI::StaleRecordError')
  end

  it 'records unknown effects after worker death and reconnects without executing again' do
    Dir.mktmpdir('ag-ui-crash-') do |directory|
      database = File.join(directory, 'runs.sqlite3')
      effects = File.join(directory, 'effects.txt')
      prepare_database(database)
      producer = worker(database, operation: 'run', effects: effects)
      expect(read_worker(producer)).to eq('READY')
      producer[0].puts('GO')
      expect(read_worker(producer)).to eq('TOOL_EFFECT_DONE')
      Process.kill('KILL', producer[3].pid)
      producer[3].join

      recovery = worker(database, operation: 'recover_and_reconnect')
      expect(read_worker(recovery)).to eq('READY')
      recovery[0].puts('GO')
      expect(JSON.parse(read_worker(recovery))).to eq(
        'result' => 'failed', 'code' => 'worker_lost', 'executed' => false, 'attached' => true, 'isolated' => true
      )
      expect(File.readlines(effects)).to eq(["effect\n"])
    ensure
      stop_worker(producer) if producer
      stop_worker(recovery) if recovery
    end
  end
end
