# frozen_string_literal: true

require 'json_schemer'

# Validates encoded AG-UI events against the pinned 1.0 JSON Schema.
#
# The schema is vendored verbatim (see spec/fixtures/schema/README.md). A test
# that only checks our own expectation of an event shape proves nothing about
# conformance; this helper checks the schema the protocol actually publishes.
module SchemaHelper
  SCHEMA_PATH = File.expand_path('../fixtures/schema/ag-ui-1.0.schema.json', __dir__)

  def schema
    @schema ||= JSONSchemer.schema(JSON.parse(File.read(SCHEMA_PATH)))
  end

  def schema_errors(payload)
    schema.validate(payload).map { |error| error['error'] || error['type'] }
  end

  # Asserts that +payload+ (a decoded event hash) is a valid AG-UI 1.0 event.
  def expect_valid_event(payload)
    errors = schema_errors(payload)
    expect(errors).to be_empty, -> { "schema errors for #{payload['type']}: #{errors.inspect}" }
  end
end

RSpec.configure do |config|
  config.include SchemaHelper
end
