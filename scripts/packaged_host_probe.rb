# frozen_string_literal: true

# Executed outside Bundler and the checkout, with only the artifact's spec added
# to GEM_HOME. Development dependencies remain available through GEM_PATH.
# Activate its dependency constraints before Rails can select a JSON version.
gem 'ruby_llm-ag_ui'
require_relative '../examples/client/database'
require 'json_schemer'

loaded = $LOADED_FEATURES.find { |file| file.end_with?('/ruby_llm/ag_ui.rb') }
abort "wrong entrypoint: #{loaded}" unless File.realpath(loaded) == File.realpath(ENV.fetch('EXPECTED_ENTRYPOINT'))
versions = %w[ruby_llm ruby_llm-ag_ui railties ag-ui-protocol].to_h do |name|
  [name, Gem.loaded_specs.fetch(name).version.to_s]
end
puts "HOST_VERSIONS: #{versions}"
schema = JSONSchemer.schema(JSON.parse(File.read(File.join(AgUiDemo::ROOT,
                                                           'spec/fixtures/schema/ag-ui-1.0.schema.json'))))

def events(response)
  abort "unexpected response #{response.status}: #{response.body}" unless response.status == 200
  response.body.lines.filter_map { |line| JSON.parse(line.delete_prefix('data: ')) if line.start_with?('data: ') }
end

AgUiDemo.with_host do |host|
  request = Rack::MockRequest.new(host)
  %w[core agent].each do |endpoint|
    body = { 'threadId' => "package-#{endpoint}", 'runId' => 'first', 'messages' => [] }
    headers = { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'text/event-stream',
                'HTTP_X_DEMO_ACTOR' => 'alice', 'HTTP_X_DEMO_SCENARIO' => 'approval', 'HTTP_HOST' => '127.0.0.1' }
    first = events(request.post("/#{endpoint}", headers.merge(input: JSON.generate(body))))
    interrupt = first.last.fetch('outcome').fetch('interrupts').fetch(0).fetch('id')
    body['runId'] = 'resume'
    body['resume'] = [{ 'interruptId' => interrupt, 'status' => 'resolved' }]
    second = events(request.post("/#{endpoint}", headers.merge(input: JSON.generate(body))))
    abort 'not successful' unless second.last['outcome'] == { 'type' => 'success' }
    abort 'progress missing' unless second.count { |event| event['type'] == 'ACTIVITY_SNAPSHOT' } == 2
    replay = events(request.post("/#{endpoint}", headers.merge(input: JSON.generate(body))))
    abort 'reconnect executed content again' unless replay.map { |event| event['type'] } ==
                                                    %w[RUN_STARTED STATE_SNAPSHOT RUN_FINISHED]
    abort 'tool executed twice' unless AgUiDemo::REGISTRY.stats('demo:alice', body['threadId'])[:effects] == 1
    (first + second + replay).each { |event| abort "invalid #{event}" unless schema.valid?(event) }
    puts "INSTALLED_HOST_PASS: #{endpoint}, generator/migration, approval, progress, reconnect"
  end
  require_relative 'rails_example_probe'
end
