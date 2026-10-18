# frozen_string_literal: true

require_relative '../pure_ruby/scripted_chat'

module AgUiDemo
  # Synthetic host chat. Retained per actor/thread, never backed by a provider.
  class Chat < ScriptedChat
    attr_reader :turns, :effects

    def initialize(scenario)
      super()
      @scenario = scenario
      @turns = 0
      @effects = 0
    end

    def complete(&stream)
      @turns += 1
      @stream = stream
      return follow_up if @turns > 2 || (@turns > 1 && @scenario != 'approval')

      case @scenario
      when 'failure' then raise StandardError, 'fixture-secret-must-not-reach-client'
      when 'cancelled' then raise RubyLLM::CancelledError
      when 'text' then say('Hello from the offline Ruby host.')
      else super
      end
    end

    private

    def finish_the_answer
      if @decisions[TOOL_CALL.id] == :approved
        fire(:after_tool_progress, TOOL_CALL, RubyLLM::Progress.new(value: 1, total: 3, message: 'fixture-secret'))
        fire(:after_tool_progress, TOOL_CALL, RubyLLM::Progress.new(value: 3, total: 3, message: 'Finished'))
        @effects += 1
      end
      super
    end

    def follow_up
      say("Follow-up turn #{@turns} on the same conversation.")
    end

    def say(text)
      stream_chunk(text)
      assistant_message(text)
    end
  end

  # Fixture identity and chat lifetime are host-owned, shared by both endpoints.
  class Registry
    ACTORS = %w[alice bob].freeze
    SCENARIOS = %w[text approval failure cancelled].freeze

    def initialize
      @chats = {}
      @mutex = Mutex.new
    end

    def actor(headers)
      value = headers['X-Demo-Actor']
      raise RubyLLM::AgUI::MalformedInputError, 'Choose a fixture actor.' unless ACTORS.include?(value)

      "demo:#{value}"
    end

    def chat(scope, input, scenario)
      raise RubyLLM::AgUI::MalformedInputError, 'Unknown fixture scenario.' unless SCENARIOS.include?(scenario)

      @mutex.synchronize { @chats[[scope, input.thread_id]] ||= Chat.new(scenario) }
    end

    def stats(scope, thread)
      @mutex.synchronize do
        chat = @chats[[scope, thread]]
        { turns: chat&.turns || 0, effects: chat&.effects || 0 }
      end
    end
  end
end
