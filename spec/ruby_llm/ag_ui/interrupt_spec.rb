# frozen_string_literal: true

RSpec.describe RubyLLM::AgUI::Interrupt do
  let(:now) { Time.utc(2026, 10, 17, 12, 0, 0) }
  let(:expires_at) { now + 900 }

  def build(**overrides)
    described_class.new(
      id: 'i1', tool_call_id: 'tc1', arguments_digest: 'digest-1', expires_at: expires_at,
      message: 'Approve cancelling order 42?', created_at: now, **overrides
    )
  end

  describe '.create' do
    it 'generates an unguessable id so a client cannot answer another actor interrupt' do
      interrupt = described_class.create(tool_call_id: 'tc1', arguments_digest: 'd', expires_at: expires_at,
                                         created_at: now)
      other = described_class.create(tool_call_id: 'tc1', arguments_digest: 'd', expires_at: expires_at,
                                     created_at: now)
      expect(interrupt.id).to match(/\A[0-9a-f-]{36}\z/)
      expect(interrupt.id).not_to eq(other.id)
      expect(interrupt).to be_pending
    end

    it 'defaults the reason to the protocol tool approval reason' do
      interrupt = described_class.create(tool_call_id: 'tc1', arguments_digest: 'd', expires_at: expires_at)
      expect(interrupt.reason).to eq('tool_call_confirmation')
    end
  end

  describe 'expiry (FR-06)' do
    it 'is answerable before its host-owned expiry and not after' do
      interrupt = build
      expect(interrupt).to be_answerable(now)
      expect(interrupt).to be_answerable(expires_at - 1)
      expect(interrupt).not_to be_answerable(expires_at)
      expect(interrupt).to be_expired(expires_at)
    end

    it 'is never expired when the host sets no expiry' do
      expect(build(expires_at: nil)).not_to be_expired(now + 1_000_000)
    end
  end

  describe '#decide' do
    it 'returns a decided copy and leaves the original pending' do
      interrupt = build
      decided = interrupt.decide(RubyLLM::AgUI::Interrupt::APPROVED, now: now + 5)
      expect(decided).to be_approved
      expect(decided.decided_at).to eq(now + 5)
      expect(decided).to be_decided
      expect(interrupt).to be_pending
    end

    it 'refuses to overwrite a decision, so a replay cannot regrant' do
      decided = build.decide(RubyLLM::AgUI::Interrupt::DENIED, now: now)
      expect { decided.decide(RubyLLM::AgUI::Interrupt::APPROVED, now: now) }
        .to raise_error(RubyLLM::AgUI::StreamError, /already denied/)
    end

    it 'refuses an unknown decision' do
      expect { build.decide(:maybe, now: now) }
        .to raise_error(RubyLLM::AgUI::ConfigurationError, /decision/)
    end

    it 'can be cancelled without approving anything' do
      expect(build.decide(RubyLLM::AgUI::Interrupt::CANCELLED, now: now)).to be_cancelled
    end
  end

  describe '#to_protocol' do
    it 'renders the pinned Interrupt shape with only defined fields' do
      protocol = build.to_protocol
      expect(protocol).to be_a(AgUiProtocol::Core::Types::Interrupt)
      expect(protocol.id).to eq('i1')
      expect(protocol.tool_call_id).to eq('tc1')
      expect(protocol.reason).to eq('tool_call_confirmation')
      expect(protocol.expires_at).to eq(expires_at.iso8601)
    end
  end

  describe '#to_h' do
    it 'keeps host bookkeeping out of the client-facing hash' do
      expect(build.to_h.keys).to eq(%w[id toolCallId reason message expiresAt status decidedAt])
      expect(build.to_h).not_to have_key('arguments_digest')
    end
  end

  describe 'argument binding' do
    it 'exposes the arguments digest for the pre-execution comparison' do
      expect(build.arguments_digest).to eq('digest-1')
    end
  end
end
