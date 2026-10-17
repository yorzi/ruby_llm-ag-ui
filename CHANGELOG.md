# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial gem skeleton: gemspec, Zeitwerk loader, configuration, errors and the
  `RubyLLM::AgUI` namespace.
- Inbound `RunAgentInput` parsing with size and schema bounds.
- RubyLLM 2.x to AG-UI 1.0 mapping for text, tool and lifecycle events.
- Run reservation, approval interrupt/resume and the cancelled outcome.
- An SSE writer and an optional Rails adapter.
