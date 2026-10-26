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

        # A client that cannot read an event stream, and tells us so.
        NOT_ACCEPTABLE = 406
        # `resolve_chat` found no chat for the thread this actor owns.
        NOT_FOUND = 404
        # The run cannot be served: a live run already has a stream, or the
        # transport is gone.
        CONFLICT = 409

        included do
          include ::ActionController::Live
        end

        # Streams one run and returns its record. A disconnected transport does
        # not stop its worker from completing and storing the real outcome.
        # The block receives the parsed input and returns the authorized chat.
        def stream_ag_ui_run(&resolve_chat)
          if resolve_chat.nil?
            raise ConfigurationError, 'stream_ag_ui_run needs a block that returns the chat for the input'
          end

          return reject_ag_ui_request(NOT_ACCEPTABLE, accept_message) unless ag_ui_accept?

          input = ag_ui_input
          chat = resolve_chat.call(input)
          run = ag_ui_run(chat, input)

          ag_ui_stream(run)
        rescue ::RubyLLM::AgUI::InputError => e
          # Every refusal the gem itself decides carries the status it should be
          # answered with: 400 for an input that cannot be accepted, 409 for an
          # identity claimed with different input or a resume that answers
          # nothing, 413 for a body past the configured bound.
          reject_ag_ui_request(e.http_status, e.message)
        rescue ::RubyLLM::AgUI::StreamError => e
          reject_ag_ui_request(CONFLICT, e.message)
        rescue StandardError => e
          reject_ag_ui_host_error(e)
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

        def reject_ag_ui_host_error(error)
          raise error unless defined?(::ActiveRecord::RecordNotFound) && error.is_a?(::ActiveRecord::RecordNotFound)

          reject_ag_ui_request(NOT_FOUND, 'There is no such thread.')
        end

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
        # and a host must not read an unbounded body from a request into memory.
        # The errors name the status a client should be answered with.
        def ag_ui_body
          limit = RubyLLM::AgUI.config.max_input_bytes
          body = request.body.read(limit + 1)
          raise MalformedInputError, 'the request body is empty.' if body.nil? || body.strip.empty?
          raise InputTooLargeError, "the request body exceeds #{limit} bytes." if body.bytesize > limit

          JSON.parse(body)
        rescue JSON::ParserError
          raise MalformedInputError, 'the request body is not JSON.'
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
