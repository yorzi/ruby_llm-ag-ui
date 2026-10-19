# frozen_string_literal: true

RSpec.describe RubyLLM::AgUI::SSEWriter do
  subject(:writer) { described_class.new(stream) }

  let(:stream) { StringIO.new }

  def frames
    stream.string.split("\n\n").reject(&:empty?)
  end

  def start_event
    RubyLLM::AgUI::Protocol::RunStartedEvent.new(thread_id: 't1', run_id: 'r1')
  end

  def content_event(delta)
    AgUiProtocol::Core::Events::TextMessageContentEvent.new(message_id: 'm1', delta: delta)
  end

  describe '.accepts? (FR-01)' do
    it 'accepts the event stream media type and its wildcards' do
      ['text/event-stream', 'text/event-stream;q=0.9', 'text/*', '*/*', 'text/html, text/event-stream'].each do |accept|
        expect(described_class.accepts?(accept)).to be(true), "expected #{accept.inspect} to be accepted"
      end
    end

    it 'accepts a missing header, which every client may send' do
      expect(described_class.accepts?(nil)).to be(true)
      expect(described_class.accepts?('')).to be(true)
    end

    it 'rejects a client that cannot read a stream' do
      expect(described_class.accepts?('application/json')).to be(false)
      expect(described_class.accepts?('text/html;q=1.0')).to be(false)
    end
  end

  describe '#headers' do
    it 'describes an unbuffered SSE response' do
      expect(writer.headers).to eq(
        'Content-Type' => 'text/event-stream; charset=utf-8',
        'Cache-Control' => 'no-cache',
        'Connection' => 'keep-alive',
        'X-Accel-Buffering' => 'no'
      )
    end
  end

  describe '#write' do
    it 'does not disguise an encoder defect as a disconnected client' do
      encoder = instance_double(AgUiProtocol::EventEncoder)
      allow(encoder).to receive(:encode).and_raise(ArgumentError, 'bad event')

      expect { described_class.new(stream, encoder: encoder).write(start_event) }
        .to raise_error(ArgumentError, 'bad event')
    end

    it 'writes one schema-valid SSE frame per event' do
      writer.write(start_event)
      writer.write(content_event('Hel'))
      expect(frames.length).to eq(2)
      expect(frames.first).to start_with('data: ')
      expect(stream.string).to end_with("\n\n")
    end

    it 'counts events and bytes' do
      frame = writer.write(start_event)
      expect(writer.events_written).to eq(1)
      expect(writer.bytes_written).to eq(frame.bytesize)
      expect(writer.bytes_written).to be > 0
    end

    it 'flushes after every event so the client is not left waiting' do
      flushes = 0
      flusher = Class.new do
        define_method(:write) { |_frame| nil }
        define_method(:flush) { flushes += 1 }
      end.new
      described_class.new(flusher).write(start_event)
      expect(flushes).to eq(1)
    end

    it 'encodes every event through the protocol encoder' do
      writer.write(start_event)
      payload = JSON.parse(frames.first.sub(/\Adata: /, ''))
      expect(payload).to include('type' => 'RUN_STARTED', 'threadId' => 't1', 'runId' => 'r1')
      expect_valid_event(payload)
    end
  end

  describe 'a dead stream (FR-05)' do
    let(:stream) { Class.new { def write(_frame) = raise(Errno::EPIPE) }.new }

    it 'normalizes the real Puma connection exception without making Puma a runtime dependency' do
      require 'puma'
      require 'puma/server'
      dead = Object.new
      dead.define_singleton_method(:write) { |_frame| raise Puma::ConnectionError, 'private socket' }
      writer = described_class.new(dead)

      expect { writer.write(start_event) }.to raise_error(RubyLLM::AgUI::TransportError)
      expect(writer).to be_closed
    end

    it 'reports a transport truncation without echoing the socket error' do
      expect { writer.write(start_event) }.to raise_error(RubyLLM::AgUI::StreamError, /EPIPE/)
    end

    it 'stays closed after the client is gone' do
      expect { writer.write(start_event) }.to raise_error(RubyLLM::AgUI::StreamError)
      expect(writer).to be_closed
      expect { writer.write(start_event) }
        .to raise_error(RubyLLM::AgUI::StreamError, /closed/)
      expect(writer.events_written).to eq(0)
    end

    it 'logs only the error class, never the error message' do
      warnings = []
      logger = instance_double(Logger, warn: nil)
      allow(logger).to receive(:warn) { |message| warnings << message }
      dead = Class.new { def write(_frame) = raise(IOError, '/srv/app/secret.rb') }.new
      expect { described_class.new(dead, logger: logger).write(start_event) }
        .to raise_error(RubyLLM::AgUI::StreamError, /IOError/)
      expect(warnings.join).to include('IOError')
      expect(warnings.join).not_to include('/srv/app/secret.rb')
    end
  end

  describe '#close' do
    it 'refuses further writes once the run is over' do
      writer.close
      expect(writer).to be_closed
      expect { writer.write(start_event) }.to raise_error(RubyLLM::AgUI::StreamError, /closed/)
    end
  end

  describe 'an IO-like stream' do
    it 'works with a bare object that only responds to write' do
      sink = Class.new do
        attr_reader :data

        def write(frame) = (@data ||= +'') << frame
      end.new
      described_class.new(sink).write(start_event)
      expect(sink.data).to start_with('data: ')
    end
  end
end
