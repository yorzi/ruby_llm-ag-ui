# frozen_string_literal: true

module RubyLLM
  module AgUI
    # Writes AG-UI events to any IO-like stream as Server-Sent Events.
    #
    # The stream is whatever the host is writing a response to: a Rack response
    # body, an ActionController::Live response, a socket, a StringIO in a test.
    # The gem does not own the transport, so it does not open connections,
    # buffer frames or choose how a host relays a background job to a client.
    # What it does own is the ordering and the framing of the events it writes.
    #
    # A dead stream is reported as a StreamError and the writer stays closed.
    # The reason is a transport truncation, not a run outcome: it is never
    # evidence that the work finished, succeeded or was cancelled.
    class SSEWriter
      # The media type an SSE response must be served as.
      CONTENT_TYPE = 'text/event-stream'

      # SSE responses must not be buffered by an intermediary.
      CACHE_CONTROL = 'no-cache'

      # Keep-alive for the proxies that need it. Puma itself does not.
      CONNECTION = 'keep-alive'

      # A response that streams must not be compressed, because compression
      # buffers and withholds the frames the client is waiting for.
      NO_TRANSFORM = 'no'

      # The number of events successfully written.
      attr_reader :events_written

      # The bytes successfully written.
      attr_reader :bytes_written

      def initialize(stream, encoder: nil, logger: nil)
        @stream = stream
        # The SDK encoder always writes SSE; its accept parameter only names the
        # media type, and this gem always serves text/event-stream.
        @encoder = encoder || ::AgUiProtocol::EventEncoder.new
        @logger = logger || RubyLLM::AgUI.config.logger
        @events_written = 0
        @bytes_written = 0
        @closed = false
      end

      # Whether an Accept header means the client can read an SSE stream.
      #
      # A host calls this before opening the stream. An explicit header that
      # cannot accept `text/event-stream` is a client that will not understand
      # the response, so the host should answer 406 instead of streaming.
      def self.accepts?(accept)
        return true if accept.nil? || accept.strip.empty?

        accept.split(',').any? do |range|
          %w[text/event-stream text/* */*].include?(range.split(';').first.to_s.strip.downcase)
        end
      end

      # The Content-Type for the response the host is about to open.
      def content_type
        @encoder.content_type
      end

      # The response headers a host should send before the first event.
      def headers
        {
          'Content-Type' => "#{content_type}; charset=utf-8",
          'Cache-Control' => CACHE_CONTROL,
          'Connection' => CONNECTION,
          'X-Accel-Buffering' => NO_TRANSFORM
        }
      end

      # Encodes +event+ and writes it, then flushes so the client sees it now.
      # Returns the encoded frame.
      def write(event)
        raise StreamError, 'The event stream is closed.' if @closed

        frame = @encoder.encode(event)
        @stream.write(frame)
        flush
        @events_written += 1
        @bytes_written += frame.bytesize
        frame
      rescue IOError, SystemCallError => e
        # The client is gone. The class name is enough for the host log; the
        # message may embed a path or a socket address and is not echoed.
        @logger&.warn("[ruby_llm_ag_ui] the event stream failed: #{e.class}")
        @closed = true
        raise StreamError, "The event stream failed: #{e.class}"
      end

      # Pushes buffered bytes to the client. A no-op for a stream that cannot
      # flush, such as a Rack response body.
      def flush
        @stream.flush if @stream.respond_to?(:flush)
      end

      # Marks the stream closed. The host calls this once the run is over; a
      # later write raises.
      def close
        @closed = true
      end

      # Whether the stream can no longer take events.
      def closed?
        @closed
      end
    end
  end
end
