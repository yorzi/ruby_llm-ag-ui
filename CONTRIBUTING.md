# Contributing

Thanks for helping. This is an unofficial community gem; small, focused changes
with tests are the easiest to accept.

## Getting started

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

## Ground rules

- **Do not fork the AG-UI schema.** Where `ag-ui-protocol` lacks a 1.0 shape,
  emit a schema-valid event and open an upstream issue before a PR. The known
  gaps (the JSON input parser, the cancelled outcome, subagent events, the
  `RUN_STARTED` `protocolVersion`) are tracked in
  [docs/PROTOCOL_COVERAGE.md](docs/PROTOCOL_COVERAGE.md).
- **Never load Rails from the core.** `require 'ruby_llm/ag_ui'` must not load
  Rails, open a network connection, or read provider credentials. There is a
  spec that asserts this.
- **Do not define or reopen top-level `AgUi`.** That namespace is owned by the
  separate `ag-ui` gem. Inside `RubyLLM::AgUI`, refer to the protocol SDK as
  `::AgUiProtocol`, and write `::Rails` for the framework.
- **Do not weaken trust boundaries.** No invented events, no raw exception text
  or secrets in SSE or logs, and no approval that is not bound to the tool call
  it approves.
- Follow the [Semantic Versioning](https://semver.org) policy and add a
  CHANGELOG entry for user-visible changes.

## Tests

Every behavior change needs a test, and lifecycle, identity and security changes
need their negative case too. The acceptance IDs (FR-01..FR-08) are referenced
in spec descriptions. Offline CI uses fakes; live provider tests are opt-in and
never required.

## Commit style

Conventional Commits (`feat:`, `fix:`, `docs:`, `test:`, `chore:`, `refactor:`),
one coherent change per commit.

## Releasing

Maintainer only. Bump `lib/ruby_llm/ag_ui/version.rb`, update the CHANGELOG,
then `bundle exec rake release`.
