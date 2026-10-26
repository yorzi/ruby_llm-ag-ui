# frozen_string_literal: true

# A complete Rails host without a database, executed in an isolated process.
require 'rails'
require 'action_controller/railtie'
require 'ruby_llm/ag_ui'

class ProbeApp < Rails::Application
  config.eager_load = false
  config.secret_key_base = 'probe'
  config.logger = Logger.new(IO::NULL)
  config.action_dispatch.show_exceptions = :none
end

class ConflictsController < ActionController::Base
  include RubyLLM::AgUI::Rails::Streaming

  skip_forgery_protection
  def create
    stream_ag_ui_run do |_input|
      raise ArgumentError, 'host defect' if params[:failure] == 'host'

      raise RubyLLM::AgUI::StreamError, 'already streaming'
    end
  end
end
ProbeApp.initialize!
ProbeApp.routes.draw { post '/runs', to: 'conflicts#create' }
request = Rack::MockRequest.new(ProbeApp)
options = { 'CONTENT_TYPE' => 'application/json', 'HTTP_HOST' => '127.0.0.1',
            input: '{"threadId":"t","runId":"r","messages":[]}' }
response = request.post('/runs', options)
abort [response.status, response.body].inspect unless response.status == 409
begin
  request.post('/runs?failure=host', options)
  abort 'host error was swallowed'
rescue ArgumentError => e
  raise unless e.message == 'host defect'
end
abort 'Active Record loaded' if defined?(ActiveRecord)
puts 'ok' # rubocop:disable RSpec/Output -- result of the isolated host probe
