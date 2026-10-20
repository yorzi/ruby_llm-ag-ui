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
| Ruby | `>= 3.2` | Recorded 0.4 CI passes on 3.2.11, 3.3.12, and 3.4.11 |
| RubyLLM | `>= 2.1`, `< 3.0` | 2.1.0 and 2.1.1 pass the 0.4 CI matrix; the recorded live session uses 2.1.1 |
| `ag-ui-protocol` | `~> 0.2.0` | 0.2.0 |
| JSON | `>= 2.0`, `< 3` | 2.21.2 passes both Rails lines; JSON 3 removes the `quirks_mode` option used by Rails 8.0 |
| Rails (adapter only) | `railties`, `actionpack`, `activerecord` `>= 8.0` | Recorded 0.4 CI passes on 8.0.5.1 and 8.1.4 with Ruby 3.3/3.4 |
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

## Local 0.4 Development Verification

On 2026-10-21, the candidate passes 294 offline examples with zero failures
and two opt-in provider checks skipped. Separate runs use RubyLLM 2.1.0 and
2.1.1 on Ruby 3.3.5 with Rails 8.1.4 and JSON 2.21.2. The [0.4 candidate CI](https://github.com/yorzi/ruby_llm-ag-ui/actions/runs/39515383346)
passes all 17 jobs at `14b3c15`: six Ruby jobs across 3.2.11, 3.3.12, and
3.4.11 with both RubyLLM versions; eight Rails jobs across 8.0.5.1 and 8.1.4
on Ruby 3.3/3.4 with both versions; lint, installed-host, and browser checks.
Each suite reports 294 examples, zero failures, and two opt-in provider skips.

The maintained client passes 18 workflows and validates all 242 consumed
events. Approval assertions inspect the official client's messages as well as
the wire: one original call, one associated result, no duplicate visible text
after reconnect. The remote browser uses Chromium 156.0.8078.4; local and remote
desktop progress and 390px denial screenshots were inspected. The fixture now fires the same resumed before-tool callback
as a real RubyLLM chat. Installed-host and generated Rails model checks pass. A fixed local 66-file
artifact independently passes clean core loading, activated dependency audit,
and Rails generator migration up/down. The isolated core uses JSON 2.7.1.
The root and activated-core audit reports no findings against the recorded
advisory database. These are development artifact checks, not public downloads.

### Recorded Live Provider Session

The 2026-10-21 local session uses OpenRouter with `openai/gpt-4.1-mini`,
RubyLLM 2.1.1, and Ruby 3.3.5. Both live examples pass: streamed text, then a
synthetic tool approval/resume with its original call id, redaction, and completed
resume reconnect. The tool is not executed before approval and executes once
after it. The same command includes one offline harness example, for three
examples total with zero failures. It verifies the gem's Ruby path, not a live
provider session through the browser or a deployed Rails application.

This session first exposed duplicate tool-call starts on a real resume.
An intercepted-HTTP real-chat test reproduces that defect before the fix and
passes afterward. Text, tool results, and approval are live evidence for this
route and model only. Live cancellation, timeout timing, network loss, denial,
and other providers remain unverified. Follow
[Provider Verification]({% link _advanced/provider-verification.md %}) to reproduce.

The checked current `ag-ui-protocol` remains 0.2.0. Its missing cancelled
outcome and `RUN_STARTED.protocolVersion` still require the local protocol
shims. Their encoded events pass the pinned schema checks; no workaround is
removed solely because a new version was expected.

## Local 0.3 Development Verification

On 2026-10-19, Ruby 3.3.5, RubyLLM 2.1.1, and Rails 8.1.4 pass 284 examples
with zero failures and one opt-in provider example skipped. The 18 browser
workflows pass with `@ag-ui/client` 1.0.3, Playwright 1.64.1, and Puma 8.0.2;
all 242 consumed events validate against the pinned schema. Desktop disconnect
and 390px cancellation screenshots were inspected.

Independent Ruby processes share one SQLite file to check reservations,
approval decisions, and competing outcome writes. Write barriers force both
processes to observe the old payload before either updates it. A producer
killed after a synthetic tool effect is explicitly recovered; reconnect never
executes the tool again. Mutation checks reject removal of either SQL compare
conditions or revision validation.

The real RubyLLM chat is also checked with intercepted HTTP: cancellation at
a checkpoint makes no provider request, and a request timeout produces a
sanitized, reconnectable failure. These tests make no live provider call.
Installed-host checks pass for both endpoints and generated Rails models.
## Recorded 0.3 CI Verification

The [2026-10-20 CI run](https://github.com/yorzi/ruby_llm-ag-ui/actions/runs/39375830117)
passes all ten jobs at `aa9e035`: Ruby 3.2.11, 3.3.12, and 3.4.11; Rails
8.0.5.1 and 8.1.4 on Ruby 3.3/3.4; lint; installed-host checks; and the browser
suite on Ubuntu 24.04. Each test job passes 284 examples with zero failures
and one opt-in provider skip. The browser suite passes 18 workflows and
validates all 242 consumed events with `@ag-ui/client` 1.0.3.
It uses Playwright 1.64.1 and Chromium 156.0.8078.4. Desktop disconnection and
390px cancellation screenshots from this run were inspected.

The first candidate failed when Rails 8.0 and JSON 3 loaded a real RubyLLM
chat. Version 0.3 bounds JSON to 2.x; the passing matrix uses 2.21.2. Intercepted
HTTP tests reproduce the failure before the bound and pass after it. These
checks make no live provider call.

The [0.3.0 release workflow](https://github.com/yorzi/ruby_llm-ag-ui/actions/runs/39376258843)
passes offline tests, browser workflows, advisory checks, and installed-host
plus clean core/Rails checks. After publication, the actual GitHub and RubyGems
downloads have matching SHA-256 hashes and all 62 packaged files match the tag.
The downloaded artifact independently passes both installed endpoints and fresh
core, advisory, and Rails generator migration checks. The isolated macOS core
activates JSON 2.7.1; the remote test matrix uses 2.21.2.

## Recorded 0.2 Client Verification

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
- **Other live paths.** Only the recorded OpenRouter model's text and approval
  workflow is verified live. Browser provider sessions, other providers,
  cancellation timing, timeouts, and network-loss recovery need separate evidence.
- **Every RubyLLM patch release in the `>= 2.1, < 3.0` range.** The upper bound
  is a dependency resolver bound; verified versions are 2.1.0 and 2.1.1. Future
  2.x releases need the same checks before a compatibility claim.
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
