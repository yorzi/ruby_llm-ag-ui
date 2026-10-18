# frozen_string_literal: true

RSpec.describe RubyLLM::AgUI::RunRecord do
  let(:created_at) { Time.utc(2026, 10, 17, 12, 0, 0) }
  let(:later) { created_at + 5 }

  let(:interrupt) do
    RubyLLM::AgUI::Interrupt.new(
      id: 'i1', tool_call_id: 'tc1', arguments_digest: 'd1', expires_at: later + 900, created_at: later
    )
  end

  def build(**overrides)
    described_class.new(
      scope: 'tenant-1:user-1', thread_id: 'thread-1', run_id: 'run-1', digest: 'digest-1',
      created_at: created_at, **overrides
    )
  end

  describe 'a fresh reservation' do
    it 'starts reserved, empty and not terminal' do
      record = build
      expect(record).to be_reserved
      expect(record).not_to be_terminal
      expect(record.sequence).to eq(0)
      expect(record.interrupts).to eq([])
      expect(record.snapshot).to be_nil
      expect(record.updated_at).to eq(created_at)
      expect(record).to be_frozen
    end

    it 'refuses an unknown status' do
      expect { build(status: :running) }.to raise_error(RubyLLM::AgUI::ConfigurationError, /status/)
    end
  end

  describe '#start' do
    it 'moves a reserved run to started and is idempotent' do
      started = build.start(now: later)
      expect(started).to be_started
      expect(started.updated_at).to eq(later)
      expect(started.start(now: later + 1)).to be(started)
    end
  end

  describe 'one outcome per run (FR-05)' do
    it 'closes with a terminal status exactly once' do
      finished = build.start(now: created_at).finish(RubyLLM::AgUI::RunRecord::SUCCEEDED, now: later)
      expect(finished).to be_succeeded
      expect(finished).to be_terminal
      expect(finished.finish(RubyLLM::AgUI::RunRecord::SUCCEEDED, now: later)).to be(finished)
    end

    it 'never lets a cancelled run be reported as success' do
      cancelled = build.start(now: created_at).finish(RubyLLM::AgUI::RunRecord::CANCELLED, now: later)
      expect { cancelled.finish(RubyLLM::AgUI::RunRecord::SUCCEEDED, now: later) }
        .to raise_error(RubyLLM::AgUI::StreamError, /already ended as cancelled/)
    end

    it 'never reopens a terminal run' do
      failed = build.start(now: created_at).finish(RubyLLM::AgUI::RunRecord::FAILED, now: later)
      expect { failed.start(now: later) }.to raise_error(RubyLLM::AgUI::StreamError, /already ended/)
      expect { failed.interrupted([interrupt], now: later) }
        .to raise_error(RubyLLM::AgUI::StreamError, /already ended as failed/)
    end

    it 'refuses a non-terminal finish' do
      expect { build.finish(RubyLLM::AgUI::RunRecord::STARTED, now: later) }
        .to raise_error(RubyLLM::AgUI::ConfigurationError, /cannot finish/)
    end
  end

  describe '#advance' do
    it 'hands out strictly increasing event sequence numbers' do
      first = build.advance(now: later)
      second = first.advance(now: later)
      expect([first.sequence, second.sequence]).to eq([1, 2])
      expect(build.sequence).to eq(0)
    end
  end

  describe '#interrupted (FR-06)' do
    it 'closes an interrupted run and reports it as awaiting approval' do
      record = build.start(now: created_at).interrupted([interrupt], now: later)
      expect(record).to be_interrupted
      expect(record).to be_terminal
      expect(record).to be_awaiting_approval
      expect(record.pending_interrupts).to eq([interrupt])
      expect(record.interrupt('i1')).to be(interrupt)
      expect(record.interrupt('nope')).to be_nil
    end

    it 'requires at least one interrupt, so an interrupt outcome is never empty' do
      expect { build.start(now: created_at).interrupted([], now: later) }
        .to raise_error(RubyLLM::AgUI::ConfigurationError, /at least one interrupt/)
    end

    it 'requires an unresolved interrupt, so an answered one is not a pause' do
      decided = interrupt.decide(RubyLLM::AgUI::Interrupt::APPROVED, now: later)
      expect { build.start(now: created_at).interrupted([decided], now: later) }
        .to raise_error(RubyLLM::AgUI::ConfigurationError, /unresolved/)
    end

    it 'replaces an interrupt in place when it is answered' do
      record = build.start(now: created_at).interrupted([interrupt], now: later)
      decided = interrupt.decide(RubyLLM::AgUI::Interrupt::APPROVED, now: later)
      replaced = record.replace_interrupt(decided, now: later)
      expect(replaced.interrupt('i1')).to be_approved
      expect(replaced.pending_interrupts).to eq([])
      expect(replaced).not_to be_awaiting_approval
      expect(record.interrupt('i1')).to be_pending
    end

    it 'refuses to replace an interrupt the run does not have' do
      record = build.start(now: created_at).interrupted([interrupt], now: later)
      other = RubyLLM::AgUI::Interrupt.new(
        id: 'i2', tool_call_id: 'tc2', arguments_digest: 'd2', expires_at: later
      )
      expect { record.replace_interrupt(other, now: later) }
        .to raise_error(RubyLLM::AgUI::ConfigurationError, /no interrupt i2/)
    end
  end

  describe '#start and the reconnect snapshot (FR-05)' do
    it 'keeps host-owned state for a reconnect without touching the status' do
      record = build.start(now: created_at, snapshot: { 'step' => 2 })
      expect(record.snapshot).to eq('step' => 2)
      expect(record).to be_started
    end

    it 'starts without a snapshot when the host publishes no state' do
      expect(build.start(now: created_at).snapshot).to be_nil
    end
  end

  describe '#to_h' do
    it 'serializes the identity, status and interrupts' do
      record = build.start(now: created_at)
      expect(record.to_h.keys).to eq(
        %w[scope threadId runId digest status sequence snapshot failure interrupts createdAt updatedAt]
      )
      expect(record.to_h).to include('scope' => 'tenant-1:user-1', 'status' => 'started', 'sequence' => 0)
    end
  end

  describe '#to_storage (a durable store round trip)' do
    it 'keeps every field a resume has to re-verify, including the arguments digest' do
      record = build.start(now: later).interrupted([interrupt], now: later).replace_interrupt(
        interrupt.decide(:approved, now: later + 1), now: later + 1
      )

      stored = described_class.from_storage(record.to_storage)

      expect(stored.to_h).to eq(record.to_h)
      expect(stored.interrupts.first.arguments_digest).to eq('d1')
      expect(stored.interrupts.first).to be_approved
      expect(stored.interrupts.first.decided_at).to eq(later + 1)
    end

    it 'survives a round trip through JSON, which a column would impose' do
      failure = { 'message' => 'Sanitized.', 'code' => 'internal_error' }
      record = build.finish(described_class::FAILED, now: later, failure: failure)

      stored = described_class.from_storage(JSON.parse(JSON.generate(record.to_storage)))

      expect(stored.to_h).to eq(record.to_h)
      expect(stored.failure).to eq(failure)
      expect(stored.created_at).to eq(created_at)
      expect(stored.updated_at).to eq(later)
    end

    it 'leaves an unanswered interrupt pending, not decided' do
      record = build.start(now: later).interrupted([interrupt], now: later)

      stored = described_class.from_storage(record.to_storage)

      expect(stored.interrupts.first).to be_pending
      expect(stored.pending_interrupts.map(&:id)).to eq(['i1'])
    end
  end
end
