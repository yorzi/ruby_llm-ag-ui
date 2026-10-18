# frozen_string_literal: true

# Maintained offline host: one Rails endpoint and one plain Ruby endpoint.
require 'rails'
require 'action_controller/railtie'
require 'active_record/railtie'
require 'ruby_llm/ag_ui'
require 'puma'
require 'tmpdir'
require 'webmock'
require_relative 'demo_chat'

WebMock.disable_net_connect!(allow_localhost: true)

module AgUiDemo
  ROOT = File.expand_path('../..', __dir__)
  REGISTRY = Registry.new

  # A minimal Rails host that exercises the real streaming concern and store.
  class Application < ::Rails::Application
    config.root = ROOT
    config.eager_load = false
    config.secret_key_base = 'offline-fixture-not-a-production-secret'
    config.hosts = ['127.0.0.1', 'localhost']
    config.logger = Logger.new(IO::NULL)
    config.active_support.deprecation = :stderr
    config.active_record.dump_schema_after_migration = false
    config.action_dispatch.show_exceptions = :none
    config.action_controller.allow_forgery_protection = false
  end

  # The fixture host, not the gem, supplies identity, chats, and safe state.
  class RunsController < ActionController::Base
    include RubyLLM::AgUI::Rails::Streaming

    def create
      stream_ag_ui_run { |input| REGISTRY.chat(ag_ui_scope, input, request.headers['X-Demo-Scenario']) }
    end

    def ag_ui_scope
      REGISTRY.actor(request.headers)
    end

    def ag_ui_state
      { 'fixture' => true }
    end
  end

  # Static assets are explicitly allowlisted; no repository directory is served.
  class Host
    ASSETS = {
      '/' => ['text/html; charset=utf-8', File.join(ROOT, 'examples/client/index.html')],
      '/client.js' => ['text/javascript', File.join(ROOT, 'tmp/demo/client.js')]
    }.freeze

    def call(env)
      path = env.fetch('PATH_INFO')
      return asset(path) if ASSETS.key?(path)
      return [200, { 'content-type' => 'text/plain' }, ['ready']] if path == '/health'
      return core(env) if path == '/core' && env['REQUEST_METHOD'] == 'POST'
      return stats(env) if path == '/stats'

      Application.call(env)
    rescue RubyLLM::AgUI::InputError => e
      [e.http_status, { 'content-type' => 'text/plain' }, [e.message]]
    end

    private

    def asset(path)
      type, file = ASSETS.fetch(path)
      [200, { 'content-type' => type }, [File.read(file)]]
    end

    def core(env)
      request = Rack::Request.new(env)
      scope = REGISTRY.actor('X-Demo-Actor' => request.get_header('HTTP_X_DEMO_ACTOR'))
      input = RubyLLM::AgUI::Input.parse(request.body.read(RubyLLM::AgUI.config.max_input_bytes + 1))
      chat = REGISTRY.chat(scope, input, request.get_header('HTTP_X_DEMO_SCENARIO'))
      run = RubyLLM::AgUI::Run.new(chat: chat, input: input, scope: scope, state: { 'fixture' => true })
      [200, RubyLLM::AgUI::SSEWriter.headers, Body.new(run)]
    end

    def stats(env)
      request = Rack::Request.new(env)
      scope = REGISTRY.actor('X-Demo-Actor' => request.get_header('HTTP_X_DEMO_ACTOR'))
      [200, { 'content-type' => 'application/json' }, [JSON.generate(REGISTRY.stats(scope, request.params['thread']))]]
    end
  end

  # Rack 3 streaming body. The server flushes each yielded frame.
  class Body
    def initialize(run)
      @run = run
    end

    def each(&block)
      sink = Object.new
      sink.define_singleton_method(:write) { |frame| block.call(frame) }
      @run.stream(to: sink)
    end
  end
end

Dir.mktmpdir('ag-ui-demo-') do |temporary|
  ENV['DATABASE_URL'] = "sqlite3:#{File.join(temporary, 'runs.sqlite3')}"
  AgUiDemo::Application.initialize!
  AgUiDemo::Application.routes.draw { post '/agent', to: 'ag_ui_demo/runs#create' }
  require 'rails/generators'
  require 'rails/generators/active_record'
  Rails::Generators.find_by_namespace('ruby_llm:ag_ui:install').start([], destination_root: temporary, quiet: true)
  load Dir[File.join(temporary, 'db/migrate/*.rb')].fetch(0)
  CreateRubyLlmAgUiRuns.new.suppress_messages { CreateRubyLlmAgUiRuns.new.migrate(:up) }
  RubyLLM::AgUI.config.run_store = RubyLLM::AgUI::Rails::ActiveRecordStore.new
  server = Puma::Server.new(AgUiDemo::Host.new)
  server.add_tcp_listener('127.0.0.1', Integer(ENV.fetch('PORT', '3199')))
  %w[TERM INT].each { |signal| Signal.trap(signal) { server.stop } }
  File.write(ENV['DEMO_PID_FILE'], Process.pid.to_s) if ENV['DEMO_PID_FILE']
  server.run.join
ensure
  server&.stop(true)
  ActiveRecord::Base.connection_pool.disconnect!
end
