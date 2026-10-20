# frozen_string_literal: true

module RubyLLM
  module AgUI
    # Parses the RunAgentInput messages array into typed protocol message
    # models.
    #
    # Hosts must reconcile client history by id against their own store; the
    # gem never trusts a client message as a system instruction or a tool
    # result. This parser only guarantees the shapes the pinned schema defines,
    # so a mismatch is a clear InputError instead of a downstream surprise.
    class MessageParser # :nodoc:
      include Validation

      # The roles the pinned schema defines.
      ROLES = %w[developer system assistant user tool activity reasoning].freeze

      def initialize(logger: nil)
        @logger = logger || RubyLLM::AgUI.config.logger
      end

      # Returns an array of AgUiProtocol::Core::Types message models.
      def parse(messages)
        messages.each_with_index.map { |message, index| build(message, index) }.freeze
      end

      private

      def build(value, index)
        hash = object!(value, "messages[#{index}]")
        id = identifier!(hash['id'], "messages[#{index}].id")
        role = string!(hash['role'], "messages[#{index}].role", max: 32)
        unless ROLES.include?(role)
          raise InvalidInputError, "messages[#{index}].role #{role.inspect} is not a known role."
        end

        send(:"build_#{role}", hash, index, id)
      rescue ArgumentError, KeyError, TypeError
        raise InvalidInputError, "messages[#{index}] is not a valid #{role} message."
      end

      def build_developer(hash, index, id)
        types = ::AgUiProtocol::Core::Types
        types::DeveloperMessage.new(
          id: id,
          content: string!(hash['content'], "messages[#{index}].content"),
          name: optional_string(hash['name'], "messages[#{index}].name")
        )
      end

      def build_system(hash, index, id)
        types = ::AgUiProtocol::Core::Types
        types::SystemMessage.new(
          id: id,
          content: string!(hash['content'], "messages[#{index}].content"),
          name: optional_string(hash['name'], "messages[#{index}].name")
        )
      end

      def build_user(hash, index, id)
        content = hash['content']
        unless content.is_a?(String) || content.is_a?(Array)
          raise InvalidInputError, "messages[#{index}].content must be text or an array of parts."
        end

        string!(content, "messages[#{index}].content") if content.is_a?(String)
        ::AgUiProtocol::Core::Types::UserMessage.new(
          id: id, content: content, name: optional_string(hash['name'], "messages[#{index}].name")
        )
      end

      def build_assistant(hash, index, id)
        content = hash['content']
        string!(content, "messages[#{index}].content") unless content.nil?
        ::AgUiProtocol::Core::Types::AssistantMessage.new(
          id: id,
          content: content,
          tool_calls: tool_calls(hash['toolCalls'], index),
          name: optional_string(hash['name'], "messages[#{index}].name")
        )
      end

      def build_tool(hash, index, id)
        ::AgUiProtocol::Core::Types::ToolMessage.new(
          id: id,
          content: tool_content(hash['content'], index),
          tool_call_id: identifier!(hash['toolCallId'], "messages[#{index}].toolCallId"),
          error: optional_string(hash['error'], "messages[#{index}].error")
        )
      end

      def build_activity(hash, index, id)
        activity_type = string!(hash['activityType'], "messages[#{index}].activityType", max: MAX_ID_LENGTH)
        content = object!(hash['content'], "messages[#{index}].content")
        ::AgUiProtocol::Core::Types::ActivityMessage.new(
          id: id, activity_type: activity_type, content: content
        )
      end

      def build_reasoning(hash, index, id)
        ::AgUiProtocol::Core::Types::ReasoningMessage.new(
          id: id, content: string!(hash['content'], "messages[#{index}].content")
        )
      end

      def tool_calls(value, index)
        return nil if value.nil?

        array!(value, "messages[#{index}].toolCalls").map do |call|
          object!(call, "messages[#{index}].toolCalls[]")
        end
      end

      # The schema allows a tool result to be text or an ordered list of parts.
      # ToolMessage models text only, so a structured result is serialized to
      # JSON text, which is how the schema says structured data travels.
      def tool_content(value, index)
        raise InvalidInputError, "messages[#{index}].content is required." if value.nil?

        return value if value.is_a?(String)

        array!(value, "messages[#{index}].content")
        Canonical.dump(value)
      end
    end
  end
end
