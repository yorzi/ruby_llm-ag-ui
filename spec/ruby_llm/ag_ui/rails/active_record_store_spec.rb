# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RubyLLM::AgUI::Rails::ActiveRecordStore do
  # Plain methods, not `let`: the values never vary and the examples need the
  # memoized-helper budget for the store itself.
  def scope
    'tenant-1:actor-1'
  end

  def now
    Time.utc(2026, 10, 17, 12, 0, 0)
  end

  def thread
    'thread-1'
  end

  let(:store) { described_class.new(clock: -> { now }) }

  def reserve(run_id: 'run-1', digest: 'digest-1')
    store.reserve(scope: scope, thread_id: thread, run_id: run_id, digest: digest)
  end

  def find(run_id: 'run-1')
    store.find(scope: scope, thread_id: thread, run_id: run_id)
  end

  describe 'reserving a run (FR-04, FR-05)' do
    it 'stores the identity another worker can find' do
      reservation = reserve

      expect(reservation).to be_created
      expect(reservation.record).to be_reserved
      expect(find).to be_reserved
      expect(find.digest).to eq('digest-1')
      expect(find.created_at).to eq(now)
    end

    it 'stores the record as JSON text the gem encoded' do
      reserve

      payload = RubyLLM::AgUI::Rails::Record.last.payload
      expect(payload).to be_a(String)
      expect(JSON.parse(payload)).to include('scope' => scope, 'threadId' => thread, 'runId' => 'run-1')
    end

    it 'attaches an identical retry instead of executing the turn twice' do
      reserve

      expect(reserve).to be_attached
      expect(RubyLLM::AgUI::Rails::Record.count).to eq(1)
    end

    it 'refuses the same identity carrying a different input' do
      reserve

      expect { reserve(digest: 'other') }.to raise_error(RubyLLM::AgUI::RunConflictError)
    end

    it 'refuses a scope that is not a host-built string' do
      expect { store.reserve(scope: Object.new, thread_id: thread, run_id: 'run-1', digest: 'd') }
        .to raise_error(RubyLLM::AgUI::ConfigurationError, /scope/)
    end

    it 'keeps one tenant out of another tenant run' do
      reserve

      expect(store.find(scope: 'tenant-2:actor-9', thread_id: thread, run_id: 'run-1')).to be_nil
    end
  end

  describe 'storing progress' do
    it 'round-trips a failed run, including the sanitized failure a reconnect reports' do
      failure = { 'message' => 'The run failed before it could finish.', 'code' => 'internal_error' }
      record = reserve.record.start(now: now).advance(now: now)
      store.save(record.finish(RubyLLM::AgUI::RunRecord::FAILED, now: now, failure: failure))

      stored = find
      expect(stored).to be_failed
      expect(stored.sequence).to eq(1)
      expect(stored.failure).to eq(failure)
      expect(stored.updated_at).to eq(now)
    end

    it 'refuses a record that was never reserved' do
      orphan = RubyLLM::AgUI::RunRecord.new(
        scope: scope, thread_id: thread, run_id: 'run-9', digest: 'digest-9', created_at: now
      )

      expect { store.save(orphan) }.to raise_error(RubyLLM::AgUI::InvalidRunIdentityError)
    end
  end

  describe 'the thread' do
    it 'reports the run reserved last, not the one with the largest clock reading' do
      reserve(run_id: 'run-1')
      reserve(run_id: 'run-2')

      expect(store.latest_run(scope: scope, thread_id: thread).run_id).to eq('run-2')
      expect(store.latest_run(scope: scope, thread_id: 'thread-2')).to be_nil
    end
  end

  describe 'interrupts (FR-06)' do
    def pause!(run_id: 'run-1')
      interrupt = RubyLLM::AgUI::Interrupt.new(
        id: 'i1', tool_call_id: 'tc1', arguments_digest: 'digest-1', expires_at: now + 900, created_at: now
      )
      record = reserve(run_id: run_id).record.start(now: now)
      store.save(record.interrupted([interrupt], now: now))
    end

    def redeem(decision, at: now, interrupt_id: 'i1')
      store.redeem_interrupt(
        scope: scope, thread_id: thread, interrupt_id: interrupt_id, decision: decision, now: at
      )
    end

    it 'keeps the interrupt a later resume answers, with its arguments digest' do
      pause!

      stored = store.latest_interrupted(scope: scope, thread_id: thread)
      expect(stored).to be_interrupted
      expect(stored.pending_interrupts.map(&:id)).to eq(['i1'])
      expect(store.find_interrupt(scope: scope, thread_id: thread, interrupt_id: 'i1')).to be_pending
    end

    it 'finds an older interrupted run behind newer runs that ended otherwise' do
      pause!(run_id: 'run-1')
      store.save(reserve(run_id: 'run-2').record.start(now: now).finish(:succeeded, now: now))
      reserve(run_id: 'run-3')

      expect(store.latest_interrupted(scope: scope, thread_id: thread).run_id).to eq('run-1')
      expect(store.find_interrupt(scope: scope, thread_id: thread, interrupt_id: 'i1')).to be_pending
      expect(redeem(:approved)).to be_recorded
      expect(store.latest_interrupted(scope: scope, thread_id: thread).interrupts.first).to be_approved
    end

    it 'records the first decision and reports a repeated one as a replay' do
      pause!

      first = redeem(:approved)
      second = redeem(:approved, at: now + 1)

      expect(first.recorded?).to be(true)
      expect(second.replayed?).to be(true)
      expect(second.interrupt).to be_approved
      expect(store.find_interrupt(scope: scope, thread_id: thread, interrupt_id: 'i1')).to be_approved
    end

    it 'refuses a second answer that disagrees, recording nothing' do
      pause!
      redeem(:approved)

      expect { redeem(:cancelled) }.to raise_error(RubyLLM::AgUI::ResumeRejectedError, /already approved/)
    end

    it 'refuses an expired interrupt' do
      pause!

      expect { redeem(:approved, at: now + 901) }
        .to raise_error(RubyLLM::AgUI::ResumeRejectedError, /expired/)
    end

    it 'refuses an unknown interrupt' do
      pause!

      expect { redeem(:approved, interrupt_id: 'nope') }
        .to raise_error(RubyLLM::AgUI::ResumeRejectedError, /no interrupt nope/)
    end

    it 'refuses a decision that is not one of the interrupt decisions' do
      pause!

      expect { redeem(:maybe) }.to raise_error(RubyLLM::AgUI::ConfigurationError, /decision/)
    end
  end
end
