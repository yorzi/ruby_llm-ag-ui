# frozen_string_literal: true

require 'json'
require 'json_schemer'

schema = JSONSchemer.schema(JSON.parse(File.read('spec/fixtures/schema/ag-ui-1.0.schema.json')))
files = Dir[File.join(ARGV.fetch(0), '**/events.json')]
abort 'No client event evidence was captured' if files.empty?
count = 0
files.each do |file|
  JSON.parse(File.read(file)).each do |event|
    errors = schema.validate(event).to_a
    abort "#{file}: #{event['type']}: #{errors}" unless errors.empty?

    count += 1
  end
end
puts "CLIENT_SCHEMA_PASS: #{count} browser-consumed events across #{files.length} scenarios"
