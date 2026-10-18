# frozen_string_literal: true

# The host's side of an AG-UI run: authenticate, authorize, and hand the gem a
# chat. Everything else — parsing the input, ordering the events, reserving the
# run, writing the SSE stream — is the concern's.
class AgentRunsController < ApplicationController
  include RubyLLM::AgUI::Rails::Streaming

  before_action :authenticate_actor!

  # POST /agent
  def create
    stream_ag_ui_run { |input| chat_for(input) }
  end

  private

  # Who the request is from. A real app reads its session, token or signed
  # identity here; this example takes a header so `curl` is enough to try it.
  def authenticate_actor!
    head :unauthorized if actor_name.nil?
  end

  def actor_name
    request.headers['X-Actor'].presence
  end

  def actor
    @actor ||= Actor.find_or_create_by!(name: actor_name)
  end

  # The scope every reservation is bounded by. It is built from the
  # authenticated actor and never from the request body: a client-supplied
  # threadId must not be able to name another actor's run.
  def ag_ui_scope
    "actor:#{actor.id}"
  end

  # AG-UI threadId → this actor's own chat, created on first sight.
  #
  # The lookup is on the actor's own association, so a threadId belonging to
  # somebody else's conversation finds nothing here and becomes a new
  # conversation for this actor rather than a way into the other one.
  # Re-authorize here when a conversation can be shared or read-only:
  # `authorize! chat` with Pundit, or a policy object of your own. An approval
  # on a resume is not a permission grant either: re-check before the approved
  # tool runs, whatever the interrupt recorded.
  def chat_for(input)
    actor.chats.find_or_create_by!(ag_ui_thread_id: input.thread_id)
  end
end
