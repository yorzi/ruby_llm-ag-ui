# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial gem skeleton: gemspec, Zeitwerk loader, configuration, errors and the
  `RubyLLM::AgUI` namespace.
- Inbound `RunAgentInput` parsing with size and schema bounds.
- RubyLLM 2.x to AG-UI 1.0 mapping for text, tool and lifecycle events, audited
  against the pinned 1.0 schema (31 event types, see `docs/PROTOCOL_COVERAGE.md`).
- Run reservation, approval interrupt/resume and the cancelled outcome.
- An SSE writer and an optional Rails adapter: a controller concern, a durable
  ActiveRecord run store and an install generator.
- Reconnect: a re-sent input for a run that already ended gets `RUN_STARTED`, its
  `STATE_SNAPSHOT` and the recorded terminal event instead of a second run.
- A runnable pure-Ruby Rack example (`examples/pure_ruby`) that works with no
  provider, and a Rails 8 endpoint example (`examples/rails_8`).
- An opt-in live-provider spec (`RUBY_LLM_LIVE=1 bundle exec rspec spec/live`).
- Documentation: architecture, protocol coverage, compatibility, Rails, security,
  licenses and upstream `ag-ui-protocol` issue drafts.

### Fixed

- A second turn on the same chat no longer leaks the previous run's message ids,
  steps and text into its own stream. RubyLLM's callbacks are additive, so the
  callbacks a finished run registered stay attached; a mapper is now final after
  it closes its run.
- A refused request is answered with the status the error names (413 for a body
  past the configured limit, not 400).
- The generated migration targets the host's Rails version instead of a
  hardcoded `7.1`.
- The durable store writes the run record as JSON text the gem encodes, so it no
  longer depends on the host's ActiveSupport JSON encoder (which breaks on
  Rails 8.0 with `json` 3.x).
