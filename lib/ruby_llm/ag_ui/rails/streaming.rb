# frozen_string_literal: true

module RubyLLM
  module AgUI
    module Rails
      # The controller concern that serves one AG-UI run as one SSE response.
      #
      #   class AgentRunsController < ApplicationController
      #     include RubyLLM::AgUI::Rails::Streaming
      #
      #     def create
      #       stream_ag_ui_run do |input|
      #         chat = ag_ui_chats.find_by!(ag_ui_thread_id: input.thread_id)
      #         authorize! chat
      #         chat
      #       end
      #     end
      #   end
      #
      # What the host owns, and the concern never guesses:
      #
      # * authentication (a `before_action`, or the action itself);
      # * `#ag_ui_scope`, the tenant/actor key the store is bounded by — the
      #   concern refuses to run without one, so an unauthenticated request
      #   cannot reserve a run;
      # * the chat the block returns, built with only the tools and the model
      #   that actor may use. The client's `messages`, `tools` and `state` are
      #   data for that chat; they authorize nothing.
      #
      # Refusals are decided before the response is committed, so a client that
      # cannot read an event stream, or that sent an input the gem will not
      # accept, gets a status code instead of half a run.
      module Streaming
        extend ::ActiveSupport::Concern

        included do
          include ::ActionController::Live
        end

        # Streams one run and returns the run's record, or nil when the client
        # disconnected. The block receives the parsed input and returns the chat
        # for it.
        def stream_ag_ui_run(&resolve_chat)
          if resolve_chat.nil?
            raise ConfigurationError, 'stream_ag_ui_run needs a block that returns the chat for the input'
          end

          return reject_ag_ui_request(:not_acceptable, accept_message) unless ag_ui_accept?

          input = ag_ui_input
          chat = resolve_chat.call(input)
          run = ag_ui_run(chat, input)

          ag_ui_stream(run)
        rescue ::RubyLLM::AgUI::InvalidInputError => e
          reject_ag_ui_request(:bad_request, e.message)
        rescue ::ActiveRecord::RecordNotFound
          reject_ag_ui_request(:not_found, 'There is no such thread.')
        rescue ::RubyLLM::AgUI::RunConflictError, ::RubyLLM::AgUI::ResumeRejectedError,
               ::RubyLLM::AgUI::StreamError => e
          reject_ag_ui_request(:conflict, e.message)
        end

        # The tenant/actor key every reservation is bounded by.
        #
        # It must come from the authenticated request, not from the input: a
        # client-chosen scope would let one actor attach to another's run.
        def ag_ui_scope
          raise ConfigurationError,
                "#{self.class} must define #ag_ui_scope, built from the authenticated tenant and actor"
        end

        # The state to publish for a reconnect, or nil. The host's own run state
        # is not the gem's to guess.
        def ag_ui_state
          nil
        end

        private

        # Whether this client can read an event stream. An AG-UI client asks for
        # `text/event-stream`; a request that asks for something else is told so
        # instead of being streamed at.
        def ag_ui_accept?
          SSEWriter.accepts?(request.headers['Accept'])
        end

        def accept_message
          "This endpoint streams #{SSEWriter::CONTENT_TYPE}. Send `Accept: #{SSEWriter::CONTENT_TYPE}`."
        end

        def ag_ui_input
          ::RubyLLM::AgUI::Input.parse(ag_ui_body)
        end

        # The request body, bounded before it is parsed: an agent input is small,
        # and a host must not read an unbounded body from an unauthenticated
        # request into memory.
        def ag_ui_body
          limit = RubyLLM::AgUI.config.max_input_bytes
          body = request.body.read(limit + 1)
          raise InvalidInputError, 'the request body is empty.' if body.nil? || body.strip.empty?
          raise InvalidInputError, "the request body exceeds #{limit} bytes." if body.bytesize > limit

          JSON.parse(body)
        rescue JSON::ParserError
          raise InvalidInputError, 'the request body is not JSON.'
        end

        def ag_ui_run(chat, input)
          ::RubyLLM::AgUI::Run.new(
            chat: chat, input: input, scope: ag_ui_scope, state: ag_ui_state
          )
        end

        # Opens the SSE response, runs, and closes the stream whatever happens.
        #
        # A client that disconnects mid-run is not a run outcome: the record the
        # store already holds says how the run ended, and a truncated stream says
        # only that this client stopped reading.
        def ag_ui_stream(run)
          response.headers.merge!(SSEWriter.headers)
          stream = response.stream
          begin
            run.stream(to: stream)
          rescue ::ActionController::Live::ClientDisconnected, ::IOError
            nil
          rescue ::RubyLLM::AgUI::StreamError
            # Before the first write this is a refusal the client can still be
            # told about, so it goes back up. After it, the stream is already
            # broken and the record in the store is the run's outcome: a
            # truncated stream says only that this client stopped reading.
            raise unless response.committed?

            nil
          ensure
            stream.close
          end
        end

        # Renders a refusal as a plain response. Everything refused here is
        # refused before the run writes anything, so the client gets a status
        # code rather than a stream that stops mid-event.
        def reject_ag_ui_request(status, message)
          if response.committed?
            raise StreamError, 'the response is already committed; a refusal must be decided before the run starts'
          end

          response.headers['Content-Type'] = 'text/plain; charset=utf-8'
          render plain: message, status: status
        end
      end
    end
  end
end
