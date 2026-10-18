# frozen_string_literal: true

# A stand-in for RubyLLM::Chat that plays the callback contract offline.
#
# The run drives a chat through #complete and the before_tool_call /
# after_message callbacks. This fake replays those callbacks in the order
# RubyLLM 2.1.1 does (source-read; see the mapper spec for the real Chunk and
# Message shapes), so the run's specs exercise the orchestration, the ordering
# and the terminal correctness without a provider, a network call or a
# RubyLLM internal that could change under us.
#
# The script block runs inside #complete and drives the fake:
#
#   FakeChat.new do |chat|
#     chat.stream(content: 'Hello')
#     chat.reply(content: 'Hello')
#   end
class FakeChat
  # The decisions the run recorded, by tool call id.
  attr_reader :decisions

  def initialize(approvals: [], &script)
    @callbacks = Hash.new { |all, name| all[name] = [] }
    @script = script
    @approvals = approvals.map { |call| RubyLLM::ToolCall.new(**call) }
    @decisions = {}
    @paused = false
    @cancelled = false
  end

  def before_tool_call(&block)
    @callbacks[:before_tool_call] << block
  end

  def after_message(&block)
    @callbacks[:after_message] << block
  end

  def complete(&stream)
    @stream = stream
    instance_exec(self, &@script)
    raise RubyLLM::CancelledError if @cancelled
  end

  def waiting?
    @paused || !@approvals.empty?
  end

  def awaiting_approval?
    !@approvals.empty?
  end

  def pending_approvals
    @approvals
  end

  # Records an approval, the way RubyLLM's Chat#approve does: the call is no
  # longer pending.
  def approve(tool_call)
    decide(tool_call, :approved)
  end

  # Records a refusal.
  def deny(tool_call)
    decide(tool_call, :denied)
  end

  def cancelled?
    @cancelled
  end

  # --- script verbs ---------------------------------------------------------

  def stream(content: nil, **attributes)
    @stream&.call(RubyLLM::Chunk.new(role: :assistant, content: content, **attributes))
  end

  def reply(content: nil, **attributes)
    message = RubyLLM::Message.new(role: :assistant, content: content, **attributes)
    fire(:after_message, message)
    message
  end

  def tool_result(content:, tool_call_id:)
    fire(:after_message, RubyLLM::Message.new(role: :tool, content: content, tool_call_id: tool_call_id))
  end

  def call_tool(**attributes)
    fire(:before_tool_call, RubyLLM::ToolCall.new(**attributes))
  end

  def call_tools(calls)
    calls.each { |call| call_tool(**call) }
  end

  # Declares the tool calls that need a human answer, the way RubyLLM reports
  # them when the loop stops on #waiting?.
  def await(calls)
    @approvals = calls.map { |call| RubyLLM::ToolCall.new(**call) }
  end

  # Pauses the loop for something other than an approval, the way an MCP input
  # request or an unfinished MCP task does.
  def pause!
    @paused = true
  end

  def cancel!
    @cancelled = true
  end

  def fail!(error)
    raise error
  end

  private

  def fire(name, *args)
    @callbacks[name].each { |callback| callback.call(*args) }
  end

  def decide(tool_call, decision)
    id = tool_call.respond_to?(:id) ? tool_call.id : tool_call
    @decisions[id] = decision
    @approvals = @approvals.reject { |pending| pending.id == id }
    self
  end
end
