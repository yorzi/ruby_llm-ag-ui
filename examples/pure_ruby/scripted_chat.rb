# frozen_string_literal: true

# A stand-in for RubyLLM::Chat, so the example runs with no provider, no
# credentials and no network.
#
# It plays exactly the parts of RubyLLM 2.1.x that a run touches: the streaming
# block, #before_tool_call, #after_message, #waiting?, #awaiting_approval?,
# #pending_approvals, #approve and #deny — in the order RubyLLM reports them.
# What it does not do is talk to a model: the assistant's words are scripted and
# the tool it asks to run is fictional.
#
# The first #complete streams a sentence and leaves a tool call waiting on a
# human. Once #approve records a decision, the next #complete reports the tool
# result and finishes the answer.
class ScriptedChat
  # The call the script asks a human about. RubyLLM reports a complete call's
  # arguments as a parsed Hash, which is what the interrupt digests.
  TOOL_CALL = RubyLLM::ToolCall.new(
    id: 'call_cancel_42', name: 'cancel_order', arguments: { 'order_id' => 42 }
  )

  def initialize
    @callbacks = Hash.new { |all, name| all[name] = [] }
    @pending = []
    @decisions = {}
  end

  # --- the RubyLLM::Chat surface a run uses ----------------------------------

  def before_tool_call(&block)
    @callbacks[:before_tool_call] << block
  end

  def after_message(&block)
    @callbacks[:after_message] << block
  end

  # Progress callbacks are registered only when the host opts in.
  def after_tool_progress(&block)
    @callbacks[:after_tool_progress] << block
  end

  def complete(&stream)
    @stream = stream
    @decisions.empty? ? ask_for_approval : finish_the_answer
  end

  def waiting?
    @pending.any?
  end

  def awaiting_approval?
    @pending.any?
  end

  def pending_approvals
    @pending
  end

  # RubyLLM's #approve and #deny take a ToolCall or its id.
  def approve(tool_call)
    decide(tool_call, :approved)
  end

  def deny(tool_call)
    decide(tool_call, :denied)
  end

  private

  # What RubyLLM reports before it pauses: the streamed sentence, the call it
  # wants to run, and the assistant message that carries it.
  def ask_for_approval
    stream_chunk('Let me cancel order 42.')
    fire(:before_tool_call, TOOL_CALL)
    assistant_message('Cancelling order 42.', tool_calls: { TOOL_CALL.id => TOOL_CALL })
    @pending = [TOOL_CALL]
  end

  # What RubyLLM reports once the call has a decision: the tool result, then the
  # answer that follows from it.
  def finish_the_answer
    if @decisions[TOOL_CALL.id] == :approved
      tool_message('Order 42 cancelled.')
      stream_chunk('Order 42 is cancelled.')
      assistant_message('Order 42 is cancelled.')
    else
      stream_chunk('Order 42 was left alone.')
      assistant_message('I did not cancel order 42.')
    end
  end

  def decide(tool_call, decision)
    id = tool_call.respond_to?(:id) ? tool_call.id : tool_call
    @decisions[id] = decision
    @pending = @pending.reject { |call| call.id == id }
    self
  end

  def stream_chunk(content)
    @stream&.call(RubyLLM::Chunk.new(role: :assistant, content: content))
  end

  def assistant_message(content, tool_calls: nil)
    fire(:after_message, RubyLLM::Message.new(role: :assistant, content: content, tool_calls: tool_calls))
  end

  def tool_message(content)
    fire(:after_message, RubyLLM::Message.new(role: :tool, content: content, tool_call_id: TOOL_CALL.id))
  end

  def fire(name, *args)
    @callbacks[name].each { |callback| callback.call(*args) }
  end
end
