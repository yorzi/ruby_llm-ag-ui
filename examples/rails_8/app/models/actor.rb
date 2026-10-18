# frozen_string_literal: true

# The authenticated actor: the tenant boundary a run is reserved under, and the
# owner of the chats a threadId may name.
class Actor < ApplicationRecord
  has_many :chats, dependent: :destroy
end
