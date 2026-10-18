# frozen_string_literal: true

# Setup for the specs that exercise the optional Rails adapter.
#
# These are the only specs in the suite that load Rails. The core is proved
# without it: spec/integration/core_load_spec.rb runs the bare require in a
# subprocess and fails if any Rails constant came with it.
require 'active_record'
require 'action_controller'

require 'ruby_llm/ag_ui/rails/active_record_store'
require 'ruby_llm/ag_ui/rails/streaming'

ActiveRecord::Base.logger = nil
ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
ActiveRecord::Schema.verbose = false
# The migration the install generator writes, applied in memory.
ActiveRecord::Schema.define do
  create_table :ruby_llm_ag_ui_runs, force: true do |t|
    t.string :scope, null: false
    t.string :thread_id, null: false
    t.string :run_id, null: false
    t.string :digest, null: false
    t.string :status, null: false
    t.integer :sequence, null: false, default: 0
    t.text :payload, null: false
  end
  add_index :ruby_llm_ag_ui_runs, %i[scope thread_id run_id], unique: true
  add_index :ruby_llm_ag_ui_runs, %i[scope thread_id status]
end

# Doubles for the controller concern. They live here rather than in spec/support
# because they name the adapter, which the core specs must be able to load
# without.
#
# A response body that marks the response committed before it fails, which is
# what Rails has already done by the time a write reaches a client that left.
class DeadStream < StringIO
  def initialize(response)
    super()
    @response = response
  end

  def write(*)
    @response.mark_committed!
    raise IOError, 'the client is gone'
  end
end

# A stream that reports itself committed once anything is written to it.
class ResponseStream < StringIO
  def initialize(response)
    super()
    @response = response
  end

  def write(data)
    @response.mark_committed!
    super
  end
end

# The response half of an ActionController::Live request: the headers the
# concern sets, the stream it writes to, and whether anything went out.
class FakeResponse
  attr_accessor :status
  attr_reader :headers, :stream

  def initialize(drops: false)
    @headers = {}
    @committed = false
    @stream = drops ? DeadStream.new(self) : ResponseStream.new(self)
  end

  def mark_committed!
    @committed = true
  end

  def committed?
    @committed
  end
end

# The Rails surface the concern touches: the request, the response and rendering
# a refusal. The controllers below add the rest.
module ControllerDoubles
  # What the concern rendered instead of streaming, as [status, message] pairs.
  attr_reader :refusals, :response

  def initialize(accept: 'text/event-stream', body: nil, drops: false)
    @accept = accept
    @body = body
    @refusals = []
    @response = FakeResponse.new(drops: drops)
  end

  def request
    Struct.new(:headers, :body).new({ 'Accept' => @accept }, StringIO.new(@body.to_s))
  end

  def render(plain:, status:)
    response.status = status
    @refusals << [status, plain]
  end
end

# A controller that says who the actor is.
class FakeController
  include ControllerDoubles
  include RubyLLM::AgUI::Rails::Streaming

  def initialize(scope: 'tenant-1:actor-1', **)
    super(**)
    @scope = scope
  end

  def ag_ui_scope
    @scope
  end
end

# A controller that forgot to say who the actor is.
class AnonymousController
  include ControllerDoubles
  include RubyLLM::AgUI::Rails::Streaming
end

RSpec.configure do |config|
  # A durable store is shared state: examples start from an empty table.
  config.before { RubyLLM::AgUI::Rails::Record.delete_all }
end
