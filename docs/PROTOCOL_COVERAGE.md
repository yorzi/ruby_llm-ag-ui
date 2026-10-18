# Protocol coverage — AG-UI 1.0

`ruby_llm-ag_ui` speaks AG-UI 1.0. This page is the audit of what it produces
against that schema: every one of the 31 event types the 1.0 `Event` union
defines, with the status this gem gives it and why.

A producer is not required to manufacture events it has no data for. What it must
never do is emit an event the schema does not define, or claim a run succeeded
when it paused, failed or was cancelled.

## The pinned schema

| | |
|---|---|
| Repository | <https://github.com/ag-ui-protocol/ag-ui> |
| Commit | `89cedd3fd549feeee41e50e1d7c6d373e549241a` |
| File | `docs/spec/1.0/schema.json` |
| Vendored copy | `spec/fixtures/schema/ag-ui-1.0.schema.json` |
| SHA-256 | `4b5c93226838a0e72d88e6c5df20633c686c49fcb75d9be2815c6cbf9e48e71a` |

The vendored schema is what the test suite validates against, so a mapping
change fails CI rather than a client. `RubyLLM::AgUI::Protocol::SCHEMA_COMMIT`
records the commit, and `schema_valid!` in the mapper and run specs checks every
emitted event against the vendored file.

## The 31 event types

Legend:

- **produced** — emitted from real RubyLLM data on the supported path.
- **optional** — emitted only when the host opts in and real data exists.
- **host-owned** — the host owns the payload; this gem does not produce it.
- **not produced** — the producer has no data for it and never fabricates it.

### Produced (13)

| Event type | Family | When |
|---|---|---|
| `RUN_STARTED` | run | Opens a reserved run; declares `protocolVersion` and echoes the accepted input. |
| `RUN_FINISHED` | run | Success, interrupt or cancelled outcome; never a raw partial. |
| `RUN_ERROR` | run | Sanitized message and code; never raw exception text. |
| `STEP_STARTED` | run | One step per RubyLLM phase (completion, tool round). |
| `STEP_FINISHED` | run | Closed before the terminal event. |
| `TEXT_MESSAGE_START` | text | Opened on the first non-empty assistant chunk. |
| `TEXT_MESSAGE_CONTENT` | text | One delta per non-empty `chunk.content`, in order. |
| `TEXT_MESSAGE_END` | text | Closed before a tool call, a phase change or the terminal event. |
| `TOOL_CALL_START` | tool | Emitted when a call is observed before it runs. |
| `TOOL_CALL_ARGS` | tool | Arguments as received; never re-synthesized. |
| `TOOL_CALL_END` | tool | Closed before the call runs or the run ends. |
| `TOOL_CALL_RESULT` | tool | The tool result, after the host redaction policy. |
| `STATE_SNAPSHOT` | state | On a reconnect: the state the host gave the run. |

### Optional (1)

| Event type | Family | When |
|---|---|---|
| `CUSTOM` | raw/custom | Only safe, documented host extensions. Nothing in the gem emits one today. |

### Host-owned, not produced (2)

| Event type | Family | Why the gem does not produce it |
|---|---|---|
| `MESSAGES_SNAPSHOT` | state | The conversation belongs to the host. Producing one would mean re-synthesizing message ids the gem did not mint, which a client would then render as new messages. |
| `STATE_DELTA` | state | Deltas describe a change the host made. The gem never invents a patch, and it has no API that publishes one. |

### Not produced (15)

| Event type | Family | Why |
|---|---|---|
| `TEXT_MESSAGE_CHUNK` | text | Convenience form of the explicit triad; the gem emits `START`/`CONTENT`/`END`. |
| `TOOL_CALL_CHUNK` | tool | Convenience form; the gem emits the explicit triad. |
| `ACTIVITY_SNAPSHOT` | activity | No `ACTIVITY_*` projection yet; RubyLLM's progress signals are not mapped. |
| `ACTIVITY_DELTA` | activity | Same: no progress projection, and no invented patches. |
| `RAW` | raw/custom | The gem never passes provider payloads through. |
| `REASONING_START` | reasoning | Private reasoning is not emitted until a host opts in, and there is no opt-in yet. |
| `REASONING_MESSAGE_START` | reasoning | A chunk that carries thinking is ignored. |
| `REASONING_MESSAGE_CONTENT` | reasoning | Same. |
| `REASONING_MESSAGE_END` | reasoning | Nothing opens a reasoning block to close. |
| `REASONING_MESSAGE_CHUNK` | reasoning | Convenience form; not emitted. |
| `REASONING_END` | reasoning | Nothing opens a reasoning block to close. |
| `REASONING_ENCRYPTED_VALUE` | reasoning | RubyLLM 2.x exposes no encrypted reasoning value. |
| `SUBAGENT_STARTED` | subagents | RubyLLM 2.x runs one chat; there is no subagent data. |
| `SUBAGENT_FINISHED` | subagents | Same. |
| `SUBAGENT_ERROR` | subagents | Same. |

Totals: 13 produced + 1 optional + 2 host-owned + 15 not produced = **31**.

## Terminal events

One run ends exactly once, and the outcome is part of the run record before it is
written:

| Situation | Terminal event |
|---|---|
| The chat completed | `RUN_FINISHED` with `{"type":"success"}` |
| The chat paused on `requires_approval` | `RUN_FINISHED` with `{"type":"interrupt","interrupts":[...]}` |
| The chat was cancelled (`Chat#cancel`) | `RUN_FINISHED` with `{"type":"cancelled"}` |
| The run failed | `RUN_ERROR` with a sanitized `message` and a `code` |
| The chat paused on something the protocol cannot express | `RUN_ERROR` (`unsupported_run_state`), never a success |

A paused run is never a success. A cancelled run is never a success. A transport
that dies mid-run reports nothing on the wire — the record stays non-terminal and
the client can reconnect — and it is never evidence that the work finished.

## Reconnect

A client that re-sends the same `(threadId, runId)` and the same input for a run
that already ended gets:

1. `RUN_STARTED` (with `protocolVersion` and the input echo),
2. `STATE_SNAPSHOT` when the run recorded one,
3. the recorded terminal event.

It does not get the run's text or tool deltas again: replaying them would draw
the text twice, and re-running a tool would duplicate the side effect. That is
also why `MESSAGES_SNAPSHOT` is not used — the client's own conversation is the
authority, and the gem will not hand it a second, re-id'd copy.

## Where this differs from `ag-ui-protocol` 0.2.0

The community Ruby SDK (`ag-ui-protocol` 0.2.0) is what this gem encodes with, so
its gaps are visible here. Issue drafts are in
[`docs/upstream/ag-ui-protocol-0.2.0.md`](upstream/ag-ui-protocol-0.2.0.md).

| ID | Gap | This gem's handling |
|---|---|---|
| SDK-GAP-01 | No `cancelled` run outcome. | `RubyLLM::AgUI::Protocol::CancelledOutcome`, a schema-valid `cancelled` outcome. |
| SDK-GAP-02 | `RunStartedEvent` has no `protocolVersion`. | `RubyLLM::AgUI::Protocol::RunStartedEvent` adds it, defaulting to `"1.0"`. |
| SDK-GAP-03 | No JSON → `RunAgentInput` parser. | `RubyLLM::AgUI::Input.parse`, with size and schema bounds. |
| SDK-GAP-04 | No `SUBAGENT_STARTED`/`_FINISHED`/`_ERROR` constants. | Not produced: RubyLLM 2.x has no subagent data to report. |
| SDK-GAP-05 | Five legacy `THINKING_*` constants that 1.0 does not define. | Never emitted. `Coverage` excludes them from the 31 and the suite asserts it. |

The SDK defines 33 event-type constants; the 1.0 schema defines 31. The two sets
differ by exactly the five `THINKING_*` constants (SDK-only) and the three
`SUBAGENT_*` types (schema-only), and `RubyLLM::AgUI::Coverage` computes that
difference at runtime rather than hardcoding it, so an SDK upgrade that closes a
gap shows up as a failing expectation instead of a stale document.

## Checking it yourself

```ruby
require 'ruby_llm/ag_ui'

RubyLLM::AgUI::Coverage.report   # => { produced: [...], optional: [...], ... }
RubyLLM::AgUI::Coverage.entries.size          # => 31
RubyLLM::AgUI::Coverage.sdk_only_event_types  # => ["THINKING_TEXT_MESSAGE_START", ...]
RubyLLM::AgUI::Coverage.schema_only_event_types # => ["SUBAGENT_STARTED", ...]
```

Every event the mapper and the run emit is validated against the vendored schema
in the spec suite (`bundle exec rspec`), including the negative cases: partial
tool arguments, a nil chunk, a tool that raises, and a thinking-only chunk that
must produce no event at all.
