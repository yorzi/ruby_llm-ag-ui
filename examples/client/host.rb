# frozen_string_literal: true

# Maintained offline host: one Rails endpoint and one plain Ruby endpoint.
require 'rails'
require 'action_controller/railtie'
require 'active_record/railtie'
require 'ruby_llm/ag_ui'
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
      stream_ag_ui_run { |input| @chat = REGISTRY.checkout(ag_ui_scope, input, request.headers['X-Demo-Scenario']) }
    ensure
      @chat&.release
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
    POST_ROUTES = { '/core' => :core, '/cancel' => :cancel }.freeze

    def call(env)
      path = env.fetch('PATH_INFO')
      return asset(path) if ASSETS.key?(path)
      return [200, { 'content-type' => 'text/plain' }, ['ready']] if path == '/health'
      return send(POST_ROUTES.fetch(path), env) if env['REQUEST_METHOD'] == 'POST' && POST_ROUTES.key?(path)
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
      [200, RubyLLM::AgUI::SSEWriter.headers,
       core_body(scope, input, request.get_header('HTTP_X_DEMO_SCENARIO'))]
    end

    def core_body(scope, input, scenario)
      chat = REGISTRY.checkout(scope, input, scenario)
      run = RubyLLM::AgUI::Run.new(chat: chat, input: input, scope: scope, state: { 'fixture' => true })
      Body.new(run, chat)
    rescue StandardError
      chat&.release
      raise
    end

    def cancel(env)
      request = Rack::Request.new(env)
      scope = REGISTRY.actor('X-Demo-Actor' => request.get_header('HTTP_X_DEMO_ACTOR'))
      input = RubyLLM::AgUI::Input.parse(request.body.read(RubyLLM::AgUI.config.max_input_bytes + 1))
      status = cancel_status(scope, input)
      [status, { 'content-type' => 'application/json' }, [JSON.generate(status: status)]]
    end

    def cancel_status(scope, input)
      record = RubyLLM::AgUI.config.run_store!.find(scope: scope, thread_id: input.thread_id, run_id: input.run_id)
      return 404 if record.nil?
      return 202 if record.started? && REGISTRY.cancel(scope, input.thread_id, input.run_id)

      409
    end

    def stats(env)
      request = Rack::Request.new(env)
      scope = REGISTRY.actor('X-Demo-Actor' => request.get_header('HTTP_X_DEMO_ACTOR'))
      thread = request.params['thread']
      record = RubyLLM::AgUI.config.run_store!.latest_run(scope: scope, thread_id: thread)
      payload = REGISTRY.stats(scope, thread).merge(status: record&.status&.to_s)
      [200, { 'content-type' => 'application/json' }, [JSON.generate(payload)]]
    end
  end

  # Rack 3 streaming body. The server flushes each yielded frame.
  class Body
    def initialize(run, chat)
      @run = run
      @chat = chat
    end

    def each(&block)
      sink = Object.new
      sink.define_singleton_method(:write) { |frame| block.call(frame) }
      @run.stream(to: sink)
    ensure
      close
    end

    def close
      chat = @chat
      @chat = nil
      chat&.release
    end
  end
end
