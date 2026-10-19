# frozen_string_literal: true

# Drop at an event boundary or after a frame reaches the transport buffer.
class DisconnectStream < StringIO
  attr_reader :failures

  def initialize(at:, flush: false)
    super()
    @at = at
    @flush_failure = flush
    @failures = 0
  end

  def write(frame)
    @drop = JSON.parse(frame.delete_prefix('data: ').strip)['type'] == @at
    disconnect! if @drop && !@flush_failure
    super
  end

  def flush
    disconnect! if @drop && @flush_failure
  end

  def disconnect!
    @failures += 1
    raise Errno::EPIPE, 'private socket detail'
  end
end
