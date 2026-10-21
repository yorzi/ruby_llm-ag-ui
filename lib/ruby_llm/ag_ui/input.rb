# frozen_string_literal: true

module RubyLLM
  module AgUI
    # A validated AG-UI 1.0 RunAgentInput.
    #
    # The community Ruby SDK models RunAgentInput but has no JSON to model
    # parser, so hosts parse and authorize the body by hand. This class does
    # that once: it bounds the body size, decodes it, strips members the pinned
    # schema does not define, validates the shapes the schema requires, and
    # hands the run typed values and a stable digest for run identity.
    #
    #   input = RubyLLM::AgUI::Input.parse(request_body, max_bytes: 256_000)
    #   input.thread_id   # => "thread-1"
    #   input.resume      # => [#<RubyLLM::AgUI::ResumeEntry ...>]
    #   input.digest      # => "9f2c..."
    #
    # Nothing here grants trust. Client messages, state, tools, context and
    # forwardedProps are accepted as data only; the host decides which tools
    # and model a run may use. This gem never reconciles or appends client
    # history to the host chat. The host owns that policy.
    class Input
      # The protocol versions this gem can act on.
      SUPPORTED_PROTOCOL_VERSIONS = [Protocol::PROTOCOL_VERSION].freeze

      # Members the pinned RunAgentInput schema defines. Anything else is not
      # part of the contract and is stripped (or rejected with strict: true).
      TOP_LEVEL_KEYS = %w[
        threadId runId protocolVersion parentRunId state messages tools context forwardedProps resume
      ].freeze

      # The conversation this run belongs to.
      attr_reader :thread_id

      # Identifies this run.
      attr_reader :run_id

      # The run that spawned this one, when the client sets one.
      attr_reader :parent_run_id

      # The AG-UI protocol version the client declared, or nil when absent.
      attr_reader :protocol_version

      # The state the run starts from.
      attr_reader :state

      # The parsed conversation, as AgUiProtocol::Core::Types message models.
      attr_reader :messages

      # The client-supplied tool definitions, as frozen hashes. Never used to
      # authorize a host tool.
      attr_reader :tools

      # The client-supplied context entries, as frozen hashes.
      attr_reader :context

      # Application-specific values passed through untouched.
      attr_reader :forwarded_props

      # The resume entries answering a previous run's interrupts.
      attr_reader :resume

      # The canonical digest of the accepted input, for run identity.
      attr_reader :digest

      # Non-fatal observations made while parsing (unknown members stripped).
      attr_reader :warnings

      def self.parse(raw, max_bytes: nil, strict: false, logger: nil)
        Parser.new(raw, max_bytes: max_bytes, strict: strict, logger: logger).parse
      end

      def initialize(attributes)
        attributes = Immutable.copy(attributes)
        @thread_id = attributes[:thread_id]
        @run_id = attributes[:run_id]
        @parent_run_id = attributes[:parent_run_id]
        @protocol_version = attributes[:protocol_version]
        @state = attributes[:state]
        @messages = attributes[:messages]
        @tools = attributes[:tools]
        @context = attributes[:context]
        @forwarded_props = attributes[:forwarded_props]
        @resume = attributes[:resume]
        @digest = attributes[:digest]
        @normalized = attributes[:normalized]
        @warnings = attributes[:warnings]
        freeze
      end

      # The accepted input as a plain hash with camelCase keys and the members
      # the schema defines. Suitable for echoing as RUN_STARTED.input.
      def to_h
        @normalized
      end

      # The names of the client-supplied tools. Informational only.
      def tool_names
        @tools.filter_map { |tool| tool['name'] }
      end

      # Whether the client supplied tool definitions. Informational only: the
      # gem never registers a client tool on the host's chat.
      def client_tools?
        !@tools.empty?
      end

      # Whether this run answers a previous run's interrupts.
      def resume?
        !@resume.empty?
      end

      # The resume entry for +interrupt_id+, or nil.
      def resume_entry(interrupt_id)
        @resume.find { |entry| entry.interrupt_id == interrupt_id }
      end

      # Decodes and validates one request body.
      #
      # Kept separate from Input so the value object stays immutable and every
      # failure message stays in one place.
      class Parser # :nodoc:
        include Validation

        MAX_NESTING = 32

        def initialize(raw, max_bytes:, strict:, logger:)
          @raw = raw
          @max_bytes = max_bytes || RubyLLM::AgUI.config.max_input_bytes
          @strict = strict
          @logger = logger || RubyLLM::AgUI.config.logger
          @warnings = []
          @parts = PartBuilder.new
        end

        # The digest re-encodes the accepted values, so text that is not UTF-8
        # or a number that overflowed to Infinity is refused here as malformed
        # input rather than escaping as an encoder error.
        def parse
          document = strip_unknown_members(decode(read_body))
          validate_common(document)
          build(document)
        rescue JSON::GeneratorError
          raise MalformedInputError, 'The request body must be valid UTF-8 JSON.'
        end

        private

        def read_body
          case @raw
          when String
            bounded!(@raw.bytesize)
            @raw
          when Hash
            bounded!(Canonical.dump(@raw).bytesize)
            @raw
          when nil then raise MalformedInputError, 'The request body is empty.'
          else read_stream
          end
        end

        def read_stream
          unless @raw.respond_to?(:read)
            raise MalformedInputError, 'The request body must be a JSON object or a readable stream.'
          end

          body = @raw.read(@max_bytes + 1) || ''
          bounded!(body.bytesize)
          body
        end

        def bounded!(bytes)
          return if bytes <= @max_bytes

          raise InputTooLargeError, "The request body exceeds the #{@max_bytes} byte limit."
        end

        def decode(body)
          source = body.is_a?(String) ? body : Canonical.dump(body)
          parsed = JSON.parse(source, max_nesting: MAX_NESTING)
          raise MalformedInputError, 'The request body must be a JSON object.' unless parsed.is_a?(Hash)

          parsed
        rescue JSON::ParserError
          raise MalformedInputError, 'The request body is not valid JSON.'
        end

        def strip_unknown_members(document)
          unknown = document.keys - TOP_LEVEL_KEYS
          reject_unknown!(unknown) if @strict && !unknown.empty?
          unknown.sort.each { |key| warn_unknown(key) }
          document.slice(*TOP_LEVEL_KEYS)
        end

        def reject_unknown!(unknown)
          raise InvalidInputError, "Unknown RunAgentInput members: #{unknown.sort.join(', ')}."
        end

        def warn_unknown(key)
          @warnings << "stripped unknown RunAgentInput member #{key.inspect}"
          @logger&.warn("[ruby_llm_ag_ui] stripped unknown RunAgentInput member #{key.inspect}")
        end

        def validate_common(document)
          document['threadId'] = identifier!(document['threadId'], 'threadId')
          document['runId'] = identifier!(document['runId'], 'runId')
          document['parentRunId'] = identifier!(document['parentRunId'], 'parentRunId') if document.key?('parentRunId')
          validate_protocol_version(document['protocolVersion'])
          document['messages'] = array!(document['messages'], 'messages', required: true)
          validate_messages_count(document['messages'])
          document['tools'] = array!(document['tools'], 'tools', max: RubyLLM::AgUI.config.max_tools)
          document['context'] = array!(document['context'], 'context', max: RubyLLM::AgUI.config.max_context)
          document['resume'] = array!(document['resume'], 'resume')
          document['state'] ||= {}
          document['forwardedProps'] ||= {}
        end

        def validate_protocol_version(value)
          return if value.nil?
          return if value.is_a?(String) && SUPPORTED_PROTOCOL_VERSIONS.include?(value)

          raise UnsupportedProtocolVersionError,
                "Unsupported protocolVersion #{value.inspect}. " \
                "This producer speaks #{SUPPORTED_PROTOCOL_VERSIONS.join(', ')}."
        end

        def validate_messages_count(messages)
          max = RubyLLM::AgUI.config.max_messages
          return if messages.size <= max

          raise InputTooLargeError, "messages exceeds the #{max} message limit."
        end

        def build(document)
          Input.new(
            thread_id: document['threadId'],
            run_id: document['runId'],
            parent_run_id: document['parentRunId'],
            protocol_version: document['protocolVersion'],
            state: document['state'],
            messages: MessageParser.new(logger: @logger).parse(document['messages']),
            tools: @parts.tools(document['tools']),
            context: @parts.context(document['context']),
            forwarded_props: document['forwardedProps'],
            resume: @parts.resume(document['resume']),
            digest: Canonical.digest(document),
            normalized: Canonical.sort(document),
            warnings: @warnings.dup.freeze
          )
        end
      end

      # Builds the composite members of a RunAgentInput: the client tool
      # definitions, the context entries and the resume entries.
      class PartBuilder # :nodoc:
        include Validation

        def tools(values)
          values.map { |value| build_tool(value) }.freeze
        end

        def context(values)
          values.map { |value| build_context(value) }.freeze
        end

        def resume(values)
          values.map { |value| build_resume(value) }.freeze
        end

        private

        def build_tool(value)
          hash = object!(value, 'tools[]')
          {
            'name' => identifier!(hash['name'], 'tools[].name'),
            'description' => optional_string(hash['description'], 'tools[].description'),
            'parameters' => hash['parameters']
          }.freeze
        end

        def build_context(value)
          hash = object!(value, 'context[]')
          {
            'description' => string!(hash['description'], 'context[].description'),
            'value' => string!(hash['value'], 'context[].value')
          }.freeze
        end

        def build_resume(value)
          hash = object!(value, 'resume[]')
          status = string!(hash['status'], 'resume[].status', max: 32)
          unless ResumeEntry::STATUSES.include?(status)
            raise InvalidInputError, "resume[].status must be one of #{ResumeEntry::STATUSES.join(', ')}."
          end

          ResumeEntry.new(
            interrupt_id: identifier!(hash['interruptId'], 'resume[].interruptId'),
            status: status,
            payload: hash['payload']
          )
        end
      end
    end
  end
end
