# frozen_string_literal: true

# The two columns AG-UI needs on the app's own chat table: who owns the
# conversation, and which threadId names it. Run `rails g ruby_llm:install`
# first: this migration extends the `chats` table that generator creates.
class AddAgUiColumnsToChats < ActiveRecord::Migration[8.0]
  def change
    # Match the primary key type `rails g ruby_llm:install` used for `chats`.
    add_column :chats, :actor_id, :bigint
    add_column :chats, :ag_ui_thread_id, :string

    # A threadId is unique per actor, which is the lookup the controller makes.
    add_index :chats, %i[actor_id ag_ui_thread_id], unique: true
  end
end
