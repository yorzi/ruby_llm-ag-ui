# frozen_string_literal: true

# One AG-UI conversation. `acts_as_chat` is RubyLLM's; the AG-UI columns are
# this app's, because an AG-UI threadId is how a client names a conversation.
class Chat < ApplicationRecord
  acts_as_chat

  belongs_to :actor

  # A threadId is unique per actor: one actor's thread identifiers are not a
  # namespace the whole application shares.
  validates :ag_ui_thread_id, uniqueness: { scope: :actor_id }
end
