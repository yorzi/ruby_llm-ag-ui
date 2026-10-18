# frozen_string_literal: true

require 'puma'
require_relative 'database'

AgUiDemo.with_host do |host|
  server = Puma::Server.new(host)
  server.add_tcp_listener('127.0.0.1', Integer(ENV.fetch('PORT', '3199')))
  %w[TERM INT].each { |signal| Signal.trap(signal) { server.stop } }
  File.write(ENV['DEMO_PID_FILE'], Process.pid.to_s) if ENV['DEMO_PID_FILE']
  server.run.join
ensure
  server&.stop(true)
end
