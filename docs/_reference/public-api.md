---
layout: default
title: Public API Contract
nav_order: 3
description: Build against the application API and custom-store contract proposed for 1.0.
---

# {{ page.title }}

{{ page.description }}
{: .fs-6 .fw-300 }

After reading this guide, you will know:

* Which entry points applications can depend on.
* Which values and failures cross the integration boundary.
* How to implement a custom store without depending on orchestration internals.

## Run One Authorized Turn

```ruby
input = RubyLLM::AgUI::Input.parse(request_body)
record = RubyLLM::AgUI::Run.new(
  chat: host_chat, input: input, scope: authenticated_scope, store: run_store
).stream(to: response_stream)
record.status
```

The host owns its chat, authentication, authorization, history, model, and tools.
Parsing client data never adds messages or tools to that chat. A completed run
returns its stored outcome on an exact retry; it never repeats the turn.
An active duplicate is refused. See
[Reconnects]({% link _core_features/reconnects.md %}).

Version 0.4 proposes the following application contract for 1.0. It is not a
1.0 stability promise yet. Breaking changes before 1.0 have upgrade steps.

| Entry point | Application contract |
| --- | --- |
| `RubyLLM::AgUI.configure`, `.config`, `.reset_configuration!` | Application defaults listed in [Configuration]({% link _getting_started/configuration.md %}). |
| `Input.parse(raw, max_bytes: nil, strict: false, logger: nil)` | Accept a Hash, JSON String, or readable body; return parsed identity, data, digest, warnings, and `to_h`. |
| `Run.new(...).stream(to:)` | Reserve before execution; return a `RunRecord`; serialize callbacks and detach a failed transport. `Run#record` exposes a producer's final record. |
| `SSEWriter#write`, `#flush`, `#close`, `#closed?`, `.headers` | Encode schema-valid events on an IO-like stream; direct write failures raise `TransportError`. |
| `RunRecord`, `Interrupt`, `ResumeEntry` | Read-only identity and JSON data, predicates, documented transitions, and serialization. Transitions return new values. |
| `Redaction.default`, `.none` and a host callable | Transform tool output and opt-in progress; nil uses the default redactor. |
| `Coverage` | Inspect produced and unsupported event types for the pinned schema. |

`Mapper` is an advanced event projection API. Its documented methods accept
RubyLLM chunks, messages, and tool calls; they return events and do not persist
or execute work. Prefer `Run` when you need identity and terminal guarantees.
The protocol shim's concrete model classes and constructors are implementation
details. Depend on encoded AG-UI events, not on a shim class name.

## Implement a Store

Implement the public methods on `Store::Base`: `reserve`, `find`, `latest_run`,
`latest_interrupted`, `save`, `find_interrupt`, and `redeem_interrupt`.
`recover` is supplied by the base class, or you can implement the same conditional
contract. Return `Reservation` and `Redemption` values where the interface
requires them. Their constructors and predicates are extension API.

Keep scope and run identity isolated. Reserve identities and redeem approvals
atomically. `save(record)` compares the observed revision and returns a new
record with a higher revision. Retain the return value. A stale write raises
`StaleRecordError`. A recovery never supersedes a terminal or newer outcome.
Read [Worker Recovery]({% link _advanced/worker-recovery.md %}) before using it.

Use `MemoryStore` within one process, or `Rails::ActiveRecordStore` with the
shipped migration. The verified database is SQLite. Other databases require
independent concurrency evidence.

## Handle Errors at the Right Boundary

`InputError#http_status` is 400 for malformed or invalid input, 413 for size
limits, and 409 for identity conflicts or rejected resumes. `ConfigurationError`
is a host setup error. An active duplicate raises `StreamError`; the Rails
adapter refuses it before committing the stream with 409.

A provider or tool failure becomes a sanitized `RUN_ERROR` and failed record.
A cooperative cancellation becomes a cancelled outcome. A `PersistenceError`
propagates because acknowledgement may be uncertain. Inspect storage before
recovery; do not infer whether an external tool effect happened from that error.
A `RunConflictError`, including `StaleRecordError`, also propagates.

The Rails entry point is `stream_ag_ui_run { |input| authorized_chat }`.
Override `ag_ui_scope` and optionally `ag_ui_state`. Configure storage with
`config.run_store`. Private concern helpers are not extension API. Follow the
[Rails guide]({% link _advanced/rails-integration.md %}) for their signatures.

## Avoid Orchestration Internals

`Emitter`, `Resume`, `Reconnect`, `MessageParser`, input parser helpers,
`Validation`, `ErrorSanitizer`, `Persistence`, and `Immutable` are internal.
Their names, constructors, and methods can change without an application API
migration. Store private helpers and generated Rails model internals have the
same boundary.

## Next Steps

* [API Reference]({% link _reference/api-reference.md %}) - inspect source signatures.
* [Compatibility]({% link _reference/compatibility.md %}) - read tested versions and limits.
* [Upgrading]({% link _reference/upgrading.md %}) - adapt older applications.
