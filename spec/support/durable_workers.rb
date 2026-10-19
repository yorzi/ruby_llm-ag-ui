# frozen_string_literal: true

require 'open3'
require 'timeout'
require 'tmpdir'

module DurableWorkers
  def worker(database, **request)
    command = [RbConfig.ruby, '-Ilib', 'spec/fixtures/durable_worker.rb']
    input, output, errors, process = Open3.popen3(*command)
    input.puts(JSON.generate(database: database, **request))
    [input, output, errors, process]
  end

  def read_worker(child)
    Timeout.timeout(20) { child[1].gets&.strip } || raise("worker exited: #{child[2].read}")
  end

  def stop_worker(child)
    child[0].close unless child[0].closed?
    terminate_worker(child[3])
    child[1..2].each(&:close)
  end

  def terminate_worker(process)
    return if process.join(1)

    Process.kill('TERM', process.pid)
    return if process.join(5)

    Process.kill('KILL', process.pid)
    process.join
  rescue Errno::ESRCH
    process.join
  end

  def prepare_database(database, seed: nil)
    setup = worker(database, operation: 'prepare', seed: seed)
    raise 'setup failed' unless read_worker(setup) == 'PREPARED'
  ensure
    stop_worker(setup) if setup
  end

  def compete(requests:, seed: nil)
    Dir.mktmpdir('ag-ui-workers-') do |directory|
      database = File.join(directory, 'runs.sqlite3')
      prepare_database(database, seed: seed)
      run_workers(database, requests)
    end
  end

  def run_workers(database, requests)
    children = []
    # rubocop:disable-next Style/MapIntoArray -- retain already spawned children if a later spawn fails
    requests.each { |request| children << worker(database, **request) }
    release_workers(children, ready: 'READY', signal: 'GO')
    if requests.all? { |request| request[:write_barrier] }
      release_workers(children, ready: 'WRITE_READY', signal: 'COMMIT')
    end
    children.map { |child| JSON.parse(read_worker(child)) }
  ensure
    children.each { |child| stop_worker(child) }
  end

  def release_workers(children, ready:, signal:)
    children.each { |child| raise 'not ready' unless read_worker(child) == ready }
    # rubocop:disable-next Style/CombinableLoops -- every writer must observe the old state before any is released
    children.each { |child| child[0].puts(signal) }
  end
end
