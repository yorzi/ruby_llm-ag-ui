# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - Unreleased

### Changed

- Remove the unused `allow_client_history` configuration and diagnostic key.
  Client messages remain untrusted data under host-controlled history policy.
- Reject unsupported `protocol_version` configuration instead of accepting a
  setting that cannot change the producer's fixed 1.0 output.

## [0.3.0] - 2026-10-20

### Added

- Explicit stopped-worker recovery with a `worker_lost` outcome, retaining run
  identity and exposing unknown tool effects for host reconciliation.
- Atomic storage revisions and independent-process SQLite reservation,
  approval redemption, conflicting-write, and worker-death tests.
- Exact-run, actor-scoped cancellation and HTTP abort workflows in the offline
  browser example, plus real RubyLLM HTTP timeout and cancellation checkpoints
  verified without a provider connection.

### Fixed

- Continue a live run after its response transport disconnects, preserving the
  real outcome and side-effect identity instead of failing the run on a write.
- Reject stale record writes and preserve uncertain database-write outcomes.
  Disable callbacks even when a producer cannot persist its final record.
- Keep uncertain reservation and approval acknowledgements separate from run
  failures, without executing a provider turn or guessing whether a decision committed.
- Recognize Puma connection failures as disconnected transports and classify
  Faraday timeouts as `transport_timeout` instead of generic transport errors.
- Require JSON 2.x so Rails 8.0 can load a real RubyLLM chat without passing
  a removed `quirks_mode` option to JSON 3.

## [0.2.0] - 2026-10-19

### Added

- Opt-in tool progress as redacted `ACTIVITY_SNAPSHOT` events, with stable
  per-call identity and per-run or global configuration.
- Installed-artifact host checks for generated migrations, RubyLLM model setup,
  actor-scoped chat persistence, and Ruby/Rails run paths.
- A pinned official AG-UI client demo for Ruby and Rails, with browser workflow
  tests, mobile screenshots, and schema validation of consumed events.

### Fixed

- Reconnect an exact completed resume request without redeeming its approval
  again. Changed input still conflicts, and a new run cannot reuse an answered
  interrupt.
- Supply the required actor scope in the opt-in live-provider check and exercise
  its run setup offline, before provider verification.

## [0.1.0] - 2026-10-18

### Added

- Initial gem skeleton: gemspec, Zeitwerk loader, configuration, errors and the
  `RubyLLM::AgUI` namespace.
- Inbound `RunAgentInput` parsing with size and schema bounds.
- RubyLLM 2.x to AG-UI 1.0 mapping for text, tool and lifecycle events, audited
  against the pinned 1.0 schema (31 event types, see `docs/_reference/protocol-coverage.md`).
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
- Versioned GitHub Pages guides and an RDoc API reference.
- Tag-triggered RubyGems trusted publishing with dependency audits, isolated
  package installation checks, and GitHub Release assets.

### Fixed

- Register the install generator under `ruby_llm:ag_ui:install` so Rails can
  resolve the documented command.
- Require patched CGI, DNS resolution, URI and zlib runtime gems so an isolated
  install does not activate older vulnerable Ruby default libraries.
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
