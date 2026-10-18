# frozen_string_literal: true

# The actor a run is reserved under, and the owner of its conversations.
class CreateActors < ActiveRecord::Migration[8.0]
  def change
    create_table :actors do |t|
      t.string :name, null: false
      t.timestamps
    end

    add_index :actors, :name, unique: true
  end
end
