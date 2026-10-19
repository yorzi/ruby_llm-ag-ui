---
layout: default
title: "Compatibility"
nav_order: 2
description: Check the dependency versions and behaviors that this repository verifies.
---

# {{ page.title }}

{{ page.description }}
{: .fs-6 .fw-300 }

After reading this guide, you will know:

* Which runtime and protocol dependency ranges the gem supports.
* What the local and CI suites assert.
* Which client and provider claims remain unverified.

What this gem is checked against, what it is not, and what changes when a
dependency does.

## Supported versions

| Component | Range | Evidence |
|---|---|---|
| Ruby | `>= 3.2` | CI passes on 3.2.11, 3.3.12, and 3.4.11; 3.3.5 checked locally |
| RubyLLM | `>= 2.1`, `< 3.0` | 2.1.1 (callback, approval and cancellation behavior read from its source) |
| `ag-ui-protocol` | `~> 0.2.0` | 0.2.0 |
| Rails (adapter only) | `railties`, `actionpack`, `activerecord` `>= 8.0` | CI passes on 8.0.5.1 and 8.1.4 with Ruby 3.3/3.4; 8.1.4 checked locally |
| AG-UI schema | pinned commit `89cedd3fd549feeee41e50e1d7c6d373e549241a` | vendored, SHA-256 recorded in [AG-UI Protocol Coverage]({% link _reference/protocol-coverage.md %}) |

The pure-Ruby core uses `ruby_llm` and `ag-ui-protocol`, plus the patched
standard-library gems required by the gemspec. Rails,
`ToolViews`, `OpenUI` and `OddlyDock` are not runtime dependencies, and the Rails
adapter is only loaded when `Rails::Railtie` is already defined.

## What is asserted, and how

| Claim | How it is checked |
|---|---|
| `require 'ruby_llm/ag_ui'` loads no Rails, opens no connection, reads no credentials | `spec/integration/core_load_spec.rb` runs the require in a subprocess and inspects what it loaded |
| Every emitted event is a valid AG-UI 1.0 event | mapper and run specs validate each encoded event against the vendored schema (`SchemaHelper`) |
| The 31-type coverage map is the schema's own union | `spec/ruby_llm/ag_ui/coverage_spec.rb` compares the pinned list with `Coverage`, and the SDK enum at runtime |
| The SDK's five legacy `THINKING_*` constants are never counted as 1.0 | the same spec asserts `LEGACY_SDK_ONLY` is absent from the map |
| Text, tool and lifecycle sequences are ordered and closed | mapper specs, including partial arguments, a nil chunk, a tool that raises, and a thinking-only chunk |
| One outcome per run, and the outcome matches what happened | run specs: success, interrupt, cancelled, sanitized failure, unsupported pause |
| `requires_approval` → interrupt → resume executes the tool once | run specs drive a fake chat through the pause, approve, deny, replay and expiry cases |
| Identity is reserved, replayed and never re-executed | store specs (memory and ActiveRecord), run specs for conflict, reconnect and live-run refusal |
| The Rails adapter serves a run and refuses invalid requests before committing | adapter specs with a controller double, and an end-to-end `spec/integration/rails_adapter_spec.rb` |
| The installer resolves the documented command | `spec/ruby_llm/ag_ui/generators/install_generator_spec.rb` |
| The installed gem generates a working migration and initializer | `bin/verify-package --rails` generates files and migrates the table up and down in SQLite |
| `ruby_llm-ag_ui` installs outside the checkout | `bin/verify-package` resolves dependencies in a fresh gem home and loads the packaged core |

The RSpec suite runs offline with fakes and no provider credentials. Package verification uses the network only to install dependencies, then runs its core and Rails checks without a provider. Its advisory check includes the actual default-library gem versions activated by the isolated core install.

## Recorded Client Verification

On 2026-10-19, the local 0.2.0 candidate passes the maintained browser workflows
with `@ag-ui/client` 1.0.3, Playwright 1.64.1, and Chrome 155.0.8059.82 on macOS.
Both the plain Ruby and Rails endpoints use scripted chats. Checks cover text,
a second turn, approval/denial, incremental progress before completion, default
tool-result redaction, sanitized failure, cancellation, and exact completed-run
reconnect, including a completed resume run. Captured events also validate
against the pinned schema. The progress demo publishes synthetic counts through
a host policy and withholds messages; unit tests check default progress redaction.

Run `bin/check-browser` to reproduce and inspect screenshots and events under
`tmp/browser/`. `bin/check --package` separately installs the built artifact
outside the checkout, checks both endpoints, and generates RubyLLM models and
ordered example migrations to verify scoped chat persistence. This package
probe uses available development dependencies; `bin/verify-package` checks a
clean gem home with freshly resolved dependencies.

The [2026-10-19 CI run](https://github.com/yorzi/ruby_llm-ag-ui/actions/runs/39179834370)
passes all ten jobs at `4aba0dc`: the Ruby and Rails matrices above, lint,
installed-host verification, and the browser suite on Ubuntu 24.04.
The browser job uses Playwright's Chromium 156.0.8078.4 and passes all 12
scenarios, with 154 consumed events validated against the schema. Its desktop
progress and mobile denial screenshots were also inspected. These remain
synthetic checks; no live provider session is recorded.

The [0.2.0 release workflow](https://github.com/yorzi/ruby_llm-ag-ui/actions/runs/39180349362)
also passes browser, advisory, installed-host, and clean-install verification.
The published GitHub and RubyGems downloads have matching checksums. The actual
published artifact separately passes the installed-host and clean core/Rails
checks after download.

## What is not asserted

- **Other clients or versions.** CopilotKit and client versions other than the
  recorded `@ag-ui/client` version have not been verified. Schema conformance
  does not establish that every UI renders the events correctly.
- **Live providers.** `spec/live/live_run_spec.rb` is the opt-in check
  (`RUBY_LLM_LIVE=1`, plus a provider key); its provider context is skipped in the default suite. The same run setup
  is exercised separately with an offline chat. Provider behavior in 2.1.1 is derived from its source, not from a recorded
  session.
- **Every RubyLLM patch release in the `>= 2.1, < 3.0` range.** The upper bound
  is enforced by the gemspec; the verified version is 2.1.1.
- **Rails versions before 8.0.** The adapter uses `Rails.setup!` and an
  initializer, and its specs run on 8.0/8.1. It may work on 7.2 and it is not
  tested there.
- **Databases other than SQLite** for the ActiveRecord store. The store uses a
  unique index and conditional payload updates. PostgreSQL and MySQL are
  untested; the SQLite checks do not establish their concurrency behavior.

## Deliberate behavior worth knowing

These are choices, not gaps, and each has a reason:

- **Tool results are `[redacted]` by default.** Redaction keeps the payload's
  shape and withholds its content until a host opts out. A client will see
  `[redacted]` until you configure a policy.
- **A resume run emits `TOOL_CALL_RESULT` without repeating
  `TOOL_CALL_START`.** The call was already reported in the run that interrupted;
  repeating it would duplicate the call in the client's conversation.
- **`MESSAGES_SNAPSHOT` is never produced.** History is the host's, and the gem
  will not re-id it. `STATE_SNAPSHOT` is produced, on a reconnect.
- **Tool progress is opt-in.** `ACTIVITY_SNAPSHOT` carries local tool progress
  when enabled. `ACTIVITY_DELTA`, `REASONING_*`, `RAW` and `SUBAGENT_*` remain
  unproduced. A thinking-only chunk produces nothing.
- **Message ids are the gem's** (`run-<id>:a<n>`), scoped to the run, because
  RubyLLM streaming chunks carry no message id.
- **Steps are per phase** (`completion`, `tool`), named `step-<n>` per run.
- **Client-supplied tools are never registered.** `input.tools` is reported and
  ignored.
- **Two live streams for one run are refused**, not merged; a run that already
  ended is served by reconnect instead.

## When a dependency moves

**A new `ag-ui-protocol` 0.2.x** that adds a schema type will fail the coverage
spec's runtime comparison, which is the point: the map has to be updated
deliberately, with a status and a reason.

**`ag-ui-protocol` 0.3+** would need `Protocol` re-checked first: the gem
subclasses `Model` and `BaseEvent` for the cancelled outcome, the versioned
`RUN_STARTED` and the run-finished shape. The gaps listed in
the [protocol coverage guide]({% link _reference/protocol-coverage.md %}) may be closed upstream, in which case
the local subclasses should be removed rather than kept.

**A new RubyLLM 2.x minor** can change the callback contract (`before_tool_call`,
`after_message`, `complete`'s streaming block), approval state (`waiting?`,
`awaiting_approval?`, `pending_approvals`, `approve`, `deny`) or the shape of
chunks and messages. The mapper and run specs pin all of it, so an upgrade fails
loudly instead of silently dropping content. A 3.0 would need a new adapter
layer; the gemspec refuses it.

**A new AG-UI schema commit** is a deliberate change: vendor the file, update
`Protocol::SCHEMA_COMMIT` and the SHA-256 in
the [protocol coverage guide]({% link _reference/protocol-coverage.md %}), then let the coverage and schema
specs tell you what moved.

## Reporting an incompatibility

Open an issue with the versions from `RubyLLM::AgUI.config.to_h`, the event types
that went wrong, and whether a real client or a live provider was involved. A
redacted trace is enough; do not paste credentials or raw tool payloads.

## Next Steps

* [AG-UI Protocol Coverage]({% link _reference/protocol-coverage.md %}) - inspect event support.
* [Upgrading]({% link _reference/upgrading.md %}) - record breaking dependency changes.
