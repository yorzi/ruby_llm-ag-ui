# frozen_string_literal: true

RubyLLM::AgUI.configure do |config|
  # Run identity must outlive the worker that reserved it. The in-process store
  # is correct for one process; a Rails app usually runs several.
  config.run_store = RubyLLM::AgUI::Rails::ActiveRecordStore.new

  # Redaction is on by default and withholds tool result content. Replace it
  # with a policy that knows which payloads this app may publish.
  # config.redact = RubyLLM::AgUI::Redaction.method(:none)

  # How long an interrupt stays answerable, in seconds.
  # config.interrupt_ttl = 900

  # Host-side diagnostics. Never receives prompts, tool payloads or credentials.
  config.logger = Rails.logger
end
