# frozen_string_literal: true

# Builders for the RubyLLM 2.x objects the mapper consumes.
#
# The specs use real RubyLLM objects rather than doubles: the mapper's whole job
# is reading RubyLLM's own shapes (a Chunk keyed by index, a Message keyed by
# id, tool arguments as a partial String or a parsed Hash), and a double would
# only test the double.
module RubyLLMFixtures
  # A streamed fragment of an assistant response.
  def chunk(content: nil, tool_calls: nil, finish_reason: nil, thinking: nil)
    RubyLLM::Chunk.new(
      role: :assistant, content: content, tool_calls: tool_calls,
      finish_reason: finish_reason, thinking: thinking
    )
  end

  # The assistant Message RubyLLM appends once a completion ends.
  def assistant_message(content: nil, tool_calls: nil, finish_reason: :stop)
    RubyLLM::Message.new(
      role: :assistant, content: content, tool_calls: tool_calls, finish_reason: finish_reason
    )
  end

  # The tool result Message RubyLLM appends after a local tool runs.
  def tool_message(content:, tool_call_id:)
    RubyLLM::Message.new(role: :tool, content: content, tool_call_id: tool_call_id)
  end

  # A ToolCall as RubyLLM reports it.
  def tool_call(id:, name:, arguments: {})
    RubyLLM::ToolCall.new(id: id, name: name, arguments: arguments)
  end

  # Streamed tool call deltas, keyed by index the way a provider sends them: the
  # first fragment names the call, the rest carry argument bytes only.
  def streamed_tool_calls(index: 0, id: nil, name: nil, arguments: nil)
    { index => tool_call(id: id, name: name, arguments: arguments) }
  end
end

RSpec.configure do |config|
  config.include RubyLLMFixtures
end
