# frozen_string_literal: true

# Decodes the Server-Sent Events an SSEWriter wrote to an IO-like stream.
#
# The run specs read the wire the way a client does — frame by frame, in order
# — rather than calling the emitter directly, so a framing mistake cannot hide
# behind a passing example.
module SSEHelper
  # The decoded event payloads, in the order they were written.
  def decode_sse(stream)
    stream.string.split("\n\n").filter_map do |frame|
      payload = frame[/\Adata: (.*)\z/m, 1]
      JSON.parse(payload) if payload
    end
  end

  # The event types, in the order they were written.
  def event_types(stream)
    decode_sse(stream).map { |event| event['type'] }
  end
end

RSpec.configure do |config|
  config.include SSEHelper
end
