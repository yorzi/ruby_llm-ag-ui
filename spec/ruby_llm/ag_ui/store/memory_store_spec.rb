# frozen_string_literal: true

RSpec.describe RubyLLM::AgUI::Store::MemoryStore do
  subject(:store) { described_class.new(clock: -> { now }) }

  let(:now) { Time.utc(2026, 10, 17, 12, 0, 0) }
  let(:tenant) { 'tenant-1:user-1' }
  let(:expires_at) { now + 900 }

  def reserve(thread_id: 'thread-1', run_id: 'run-1', digest: 'digest-1', scope: tenant)
    store.reserve(scope: scope, thread_id: thread_id, run_id: run_id, digest: digest)
  end

  def reserve_interrupted(thread_id: 'thread-1', run_id: 'run-1')
    record = reserve(thread_id: thread_id, run_id: run_id).record
    interrupt = RubyLLM::AgUI::Interrupt.new(
      id: 'i1', tool_call_id: 'tc1', arguments_digest: 'd1', expires_at: expires_at, created_at: now
    )
    store.save(record.start(now: now).interrupted([interrupt], now: now))
    interrupt
  end

  describe '#reserve (FR-04)' do
    it 'claims the identity once and returns a reserved record' do
      reservation = reserve
      expect(reservation).to be_created
      expect(reservation).not_to be_attached
      expect(reservation.thread_id).to eq('thread-1')
      expect(reservation.run_id).to eq('run-1')
      expect(reservation.digest).to eq('digest-1')
      expect(reservation.record).to be_reserved
      expect(reservation.to_h).to include('status' => 'created')
    end

    it 'attaches an identical retry instead of starting a second run (FR-05)' do
      first = reserve
      retry_reservation = reserve
      expect(retry_reservation).to be_attached
      expect(retry_reservation.record).to be(first.record)
      expect(retry_reservation.record).to be_reserved
    end

    it 'treats the same key with different input as a conflict, never a second run' do
      reserve(digest: 'digest-1')
      expect { reserve(digest: 'digest-2') }
        .to raise_error(RubyLLM::AgUI::RunConflictError, /already reserved with a different input/)
    end

    it 'keeps tenants apart even for the same threadId and runId (FR-04)' do
      other = reserve(scope: 'tenant-2:user-9')
      expect(other).to be_created
      expect(store.find(scope: 'tenant-2:user-9', thread_id: 'thread-1', run_id: 'run-1')).to be(other.record)
      expect(store.find(scope: tenant, thread_id: 'thread-1', run_id: 'run-1')).not_to be(other.record)
    end

    it 'refuses a scope that is not a canonical non-empty string' do
      expect { reserve(scope: nil) }
        .to raise_error(RubyLLM::AgUI::ConfigurationError, /scope must be a non-empty String/)
      expect { reserve(scope: '') }
        .to raise_error(RubyLLM::AgUI::ConfigurationError, /scope must be a non-empty String/)
      expect { reserve(scope: 42) }
        .to raise_error(RubyLLM::AgUI::ConfigurationError, /scope must be a non-empty String/)
    end
  end

  describe '#save' do
    it 'persists progress and returns the record' do
      record = reserve.record
      started = store.save(record.start(now: now))
      expect(started).to be_started
      expect(store.find(scope: tenant, thread_id: 'thread-1', run_id: 'run-1')).to be(started)
    end

    it 'refuses a run that was never reserved' do
      record = RubyLLM::AgUI::RunRecord.new(
        scope: tenant, thread_id: 'thread-9', run_id: 'run-9', digest: 'd', created_at: now
      )
      expect { store.save(record) }
        .to raise_error(RubyLLM::AgUI::InvalidRunIdentityError, /was never reserved/)
    end

    it 'refuses to change the identity digest of an existing reservation' do
      record = reserve.record
      forged = RubyLLM::AgUI::RunRecord.new(
        scope: tenant, thread_id: 'thread-1', run_id: 'run-1', digest: 'forged', created_at: now
      )
      expect { store.save(forged) }.to raise_error(RubyLLM::AgUI::RunConflictError, /different input/)
      expect(store.find(scope: tenant, thread_id: 'thread-1', run_id: 'run-1')).to be(record)
    end
  end

  describe '#find' do
    it 'returns the exact run or nil' do
      record = reserve.record
      expect(store.find(scope: tenant, thread_id: 'thread-1', run_id: 'run-1')).to be(record)
      expect(store.find(scope: tenant, thread_id: 'thread-1', run_id: 'other')).to be_nil
    end
  end

  describe '#latest_run and #latest_interrupted' do
    it 'orders runs by the order they were reserved' do
      first = reserve(run_id: 'run-1').record
      second = reserve(run_id: 'run-2').record
      expect(store.latest_run(scope: tenant, thread_id: 'thread-1')).to be(second)
      expect(store.latest_interrupted(scope: tenant, thread_id: 'thread-1')).to be_nil
      expect(store.latest_run(scope: tenant, thread_id: 'thread-1')).not_to be(first)
    end

    it 'finds the most recent interrupted run even after a later run started' do
      interrupted = reserve_interrupted(run_id: 'run-1')
      expect(store.latest_interrupted(scope: tenant, thread_id: 'thread-1').interrupts).to eq([interrupted])
      reserve(run_id: 'run-2')
      expect(store.latest_interrupted(scope: tenant, thread_id: 'thread-1').run_id).to eq('run-1')
      expect(store.latest_run(scope: tenant, thread_id: 'thread-1').run_id).to eq('run-2')
    end
  end

  describe '#find_interrupt (FR-06)' do
    it 'finds an interrupt anywhere on the thread and nowhere else' do
      interrupt = reserve_interrupted
      expect(store.find_interrupt(scope: tenant, thread_id: 'thread-1', interrupt_id: 'i1')).to be(interrupt)
      expect(store.find_interrupt(scope: tenant, thread_id: 'thread-1', interrupt_id: 'nope')).to be_nil
      expect(store.find_interrupt(scope: 'tenant-2:user-9', thread_id: 'thread-1', interrupt_id: 'i1')).to be_nil
    end

    it 'requires an interrupt id' do
      expect { store.find_interrupt(scope: tenant, thread_id: 'thread-1', interrupt_id: '') }
        .to raise_error(RubyLLM::AgUI::InvalidInputError, /interrupt_id is required/)
    end
  end

  describe '#redeem_interrupt (FR-06)' do
    before { reserve_interrupted }

    it 'records the decision once and reports that this call recorded it' do
      redemption = store.redeem_interrupt(
        scope: tenant, thread_id: 'thread-1', interrupt_id: 'i1',
        decision: RubyLLM::AgUI::Interrupt::APPROVED, now: now
      )
      expect(redemption).to be_recorded
      expect(redemption).not_to be_replayed
      expect(redemption).to be_approved
      expect(redemption.tool_call_id).to eq('tc1')
      expect(redemption.interrupt.decided_at).to eq(now)
      expect(redemption.to_h).to include('interruptId' => 'i1', 'status' => 'approved', 'replayed' => false)
      expect(store.find_interrupt(scope: tenant, thread_id: 'thread-1', interrupt_id: 'i1')).to be_approved
    end

    it 'reports a repeat of the stored decision as a replay, not a second grant' do
      store.redeem_interrupt(scope: tenant, thread_id: 'thread-1', interrupt_id: 'i1',
                             decision: RubyLLM::AgUI::Interrupt::APPROVED, now: now)
      replay = store.redeem_interrupt(scope: tenant, thread_id: 'thread-1', interrupt_id: 'i1',
                                      decision: RubyLLM::AgUI::Interrupt::APPROVED, now: now + 10)
      expect(replay).to be_replayed
      expect(replay).not_to be_recorded
      expect(replay).to be_approved
      expect(replay.interrupt.decided_at).to eq(now)
    end

    it 'refuses a second answer that disagrees with the stored decision' do
      store.redeem_interrupt(scope: tenant, thread_id: 'thread-1', interrupt_id: 'i1',
                             decision: RubyLLM::AgUI::Interrupt::DENIED, now: now)
      expect do
        store.redeem_interrupt(scope: tenant, thread_id: 'thread-1', interrupt_id: 'i1',
                               decision: RubyLLM::AgUI::Interrupt::APPROVED, now: now)
      end.to raise_error(RubyLLM::AgUI::ResumeRejectedError, /already denied/)
      expect(store.find_interrupt(scope: tenant, thread_id: 'thread-1', interrupt_id: 'i1')).to be_denied
    end

    it 'refuses an expired interrupt without recording anything' do
      expect do
        store.redeem_interrupt(scope: tenant, thread_id: 'thread-1', interrupt_id: 'i1',
                               decision: RubyLLM::AgUI::Interrupt::APPROVED, now: expires_at)
      end.to raise_error(RubyLLM::AgUI::ResumeRejectedError, /expired/)
      expect(store.find_interrupt(scope: tenant, thread_id: 'thread-1', interrupt_id: 'i1')).to be_pending
    end

    it 'refuses an unknown interrupt and a wrong scope' do
      expect do
        store.redeem_interrupt(scope: tenant, thread_id: 'thread-1', interrupt_id: 'nope',
                               decision: RubyLLM::AgUI::Interrupt::APPROVED, now: now)
      end.to raise_error(RubyLLM::AgUI::ResumeRejectedError, /no interrupt/)
      expect do
        store.redeem_interrupt(scope: 'tenant-2:user-9', thread_id: 'thread-1', interrupt_id: 'i1',
                               decision: RubyLLM::AgUI::Interrupt::APPROVED, now: now)
      end.to raise_error(RubyLLM::AgUI::ResumeRejectedError, /no interrupt/)
    end

    it 'refuses an unknown decision' do
      expect do
        store.redeem_interrupt(scope: tenant, thread_id: 'thread-1', interrupt_id: 'i1', decision: :granted, now: now)
      end.to raise_error(RubyLLM::AgUI::ConfigurationError, /decision/)
    end

    it 'lets exactly one concurrent caller record the decision' do
      results = Array.new(8) do
        Thread.new do
          store.redeem_interrupt(scope: tenant, thread_id: 'thread-1', interrupt_id: 'i1',
                                 decision: RubyLLM::AgUI::Interrupt::APPROVED, now: now)
        end
      end.map(&:value)

      expect(results.count(&:recorded?)).to eq(1)
      expect(results.count(&:replayed?)).to eq(7)
      expect(store.find_interrupt(scope: tenant, thread_id: 'thread-1', interrupt_id: 'i1')).to be_approved
    end
  end

  describe 'the interface' do
    it 'is a Store::Base and inherits its documented contract' do
      expect(described_class.ancestors).to include(RubyLLM::AgUI::Store::Base)
    end

    it 'raises NotImplementedError from the unimplemented base' do
      expect { RubyLLM::AgUI::Store::Base.new.reserve(scope: tenant, thread_id: 't', run_id: 'r', digest: 'd') }
        .to raise_error(NotImplementedError)
    end
  end
end
