---
layout: default
title: "How RubyLLM AG-UI Works"
nav_order: 2
description: One RubyLLM chat turn becomes one ordered AG-UI run with a single recorded outcome.
---

# {{ page.title }}

{{ page.description }}
{: .fs-6 .fw-300 }

After reading this guide, you will know:

* Which objects parse input, drive a chat, write events, and store run state.
* How the event stream and terminal outcome are ordered.
* Which responsibilities stay with the host application.

One RubyLLM chat turn is one AG-UI run. A run has one identity, one ordered
stream of events and exactly one outcome, and the parts that decide those things
are small enough to name:

```
POST RunAgentInput
        │
        ▼
┌──────────────────┐   bounded, validated, typed   ┌────────────────┐
│ Input.parse      │──────────────────────────────▶│ Run            │
└──────────────────┘   + canonical digest          └────────────────┘
                                                      │  │  │  │
                          reserve (scope, thread, run) │  │  │  │
                                    ┌─────────────────┘  │  │  │
                                    ▼                    │  │  │
                              ┌───────────┐              │  │  │
                              │ RunStore  │◀─────────────┘  │  │
                              └───────────┘   save/attach   │  │
                                                             │  │
             chat.complete { chunk }  ──▶  ┌─────────┐  events │  │
             chat.before_tool_call   ──▶  │ Mapper  │─────────┘  │
             chat.after_message      ──▶  └─────────┘            │
                                                                 ▼
                                     ┌──────────┐   one frame  ┌──────────┐
                                     │ Emitter  │─────────────▶│ SSEWriter│──▶ IO
                                     └──────────┘   per event   └──────────┘
                                       record: sequence, status, terminal
```

## The boot contract

```ruby
require 'ruby_llm/ag_ui'
```

loads RubyLLM, `ag-ui-protocol`, Zeitwerk and the standard library, and nothing
else. It does not load Rails, open a network connection or read provider
credentials, and the test suite asserts that in a subprocess rather than by
inspection (`spec/integration/core_load_spec.rb`).

Two things are deliberately eager:

- **Errors** (`lib/ruby_llm/ag_ui/error.rb`) are ignored by Zeitwerk and
  `require`d directly, so a host can `rescue RubyLLM::AgUI::InputError` before
  anything has been autoloaded.
- **The namespace itself** (`RubyLLM::AgUI`, with `configure`, `config` and
  `reset_configuration!`) lives in `lib/ruby_llm/ag_ui.rb`, because everything
  else hangs off it.

The Rails adapter under `lib/ruby_llm/ag_ui/rails/` is ignored by the loader and
loaded only when `Rails::Railtie` is already defined. A pure-Ruby host never
loads ActiveRecord or ActionController.

`RubyLLM::AgUI` does not define or reopen the top-level `AgUi` namespace: that
belongs to the `ag-ui` gem, and this gem talks to the protocol SDK as
`::AgUiProtocol`. Inside the namespace the framework is `::Rails` for the same
reason.

## The pieces

| Component | Owns | Does not own |
|---|---|---|
| `Input` / `Parser` / `MessageParser` | Bounding the body, decoding JSON, stripping unknown members, validating shapes, computing the canonical `digest`. | Trust. Nothing a client sends grants a privilege. |
| `Run` | The turn: reserve identity, drive the chat, project callbacks, close and report the outcome. | Authentication, authorization, transport, chat construction. |
| `Mapper` | Which AG-UI events a RubyLLM signal becomes, and the ordering between them. Returns arrays; writes nothing. | Sequence numbers, persistence, the terminal event. |
| `Emitter` | Writing events, advancing the run record's sequence, persisting a terminal outcome before writing it, closing open content first. | Which events; the outcome. |
| `SSEWriter` | Framing events as `text/event-stream` on any object with `#write`. | The connection, buffering, keep-alive policy. |
| `Protocol` | The two 1.0 shapes `ag-ui-protocol` 0.2.0 cannot express, plus factories shared by the live and reconnect paths. | Schema evolution. |
| `Store::Base` / `MemoryStore` / `Rails::ActiveRecordStore` | Run identity, interrupts, redemption. | Chat history, message ids, tool output. |
| `RunRecord` / `Interrupt` | An immutable value per run and per approval pause, with legal transitions only. | Wire shapes. |
| `Resume` / `Reconnect` | Answering a previous run's interrupts; serving a run that already ended. | Permission. A resume is a request. |
| `Redaction` / `ErrorSanitizer` | What may appear on the wire: payload shapes without content, fixed error messages and codes. | Deciding what the host considers secret; that is the host's policy. |
| `Coverage` | The 31-type audit against the pinned schema. | What the SDK supports. |

## The run, step by step

1. **Parse.** `Input.parse` bounds the body (`config.max_input_bytes`), decodes
   it, strips top-level members the pinned schema does not define (warnings are
   logged; `strict: true` rejects instead), validates message/tool/context
   counts and shapes, and freezes the result with a canonical digest.
2. **Reserve.** `Run` asks the store for `(scope, threadId, runId)`. The scope
   must be a non-empty String the host built from authenticated identity. A
   fresh key reserves; the same key with the same digest attaches; the same key
   with a different digest is a conflict; a non-terminal record that is not
   attachable is refused (`StreamError`) rather than streamed twice.
3. **Open.** `RUN_STARTED` carries `protocolVersion` and the accepted input, so
   the client can see exactly what the host accepted.
4. **Drive.** `Run` registers one `before_tool_call`, one `after_message` and
   one streaming block on the chat, then calls `Chat#complete`. RubyLLM owns the
   agent loop: model calls, tool execution, approval pauses, cancellation
   checkpoints.
5. **Project.** Each callback hands the mapper its RubyLLM value and gets back
   the events to write. The mapper is a state machine: a text message opens on
   its first non-empty chunk and closes before a tool call, a phase change or the
   terminal event; a tool call opens when its id and name are both known, streams
   its argument deltas as received, and closes before it runs; one step per phase
   (`completion`, `tool`) so consecutive steps never overlap.
6. **Write.** The emitter writes the events as SSE, advancing the run record's
   sequence by one per event.
7. **Close and report.** Open content is closed, then the outcome is persisted
   and only then written: `RUN_FINISHED` with `success`, `interrupt` or
   `cancelled`, or `RUN_ERROR` with a sanitized message and code. A chat paused
   on anything the protocol cannot express is a failure, not a success.

## Invariants

- **One outcome per run.** `RunRecord` transitions from `reserved` to `started`
  and then to exactly one of `succeeded`, `interrupted`, `cancelled`, `failed`.
  A terminal record accepts no new start, and `finish` records the first failure
  and keeps it.
- **Content before terminal.** No run ends with a text message, tool call or step
  still open: a client that never sees `*_END` waits forever.
- **Terminal before transport.** The outcome is stored before it is written, so
  a socket that dies after the decision cannot cause a second execution.
- **Sequence, not wall clock.** Every event advances the record's sequence; a
  reconnect orders what it serves by that number.
- **Delta replay is forbidden.** A reconnect serves `RUN_STARTED`,
  `STATE_SNAPSHOT` (when recorded) and the terminal event. Never text or tool
  deltas: replaying them draws text twice, and re-running a tool repeats the
  side effect.
- **Closed is final.** RubyLLM's callbacks are additive and cannot be removed, so
  the callbacks a run registered stay attached to the chat. A mapper that has
  closed its run therefore maps nothing further; the next turn is a different run
  with its own ids, sequence and record.

## Concurrency

RubyLLM may run local tools on worker threads and appends tool results in the
caller's thread, so `Run` maps and writes under one mutex. That keeps the event
order consistent with the mapper's state; it does not make a run parallel.

Two streams for one live run are refused, not merged: relaying one run to two
clients is a transport the gem does not own. Two requests for one run identity
are resolved by the store, and the store's redemption step is the authoritative
race guard for a resume. The loser is told the answer was already recorded
instead of running the tool twice.

## Storage

A record is a value object; stores keep values. `RunRecord#to_h` is the reporting
shape (no interrupt argument digests, no creation times), and `#to_storage` is
the durable shape a store round-trips through JSON. `ruby_llm_ag_ui_runs` (the
Rails store) is one row per run: scope, thread, run, digest, status, sequence,
snapshot, failure, interrupts.

Why the scope must be a String: an arbitrary object hashes by identity, so the
same actor would produce a different key on the next request and a retry would
execute the run again. A String built from authenticated identity is stable
across requests and processes, which is the property the reservation needs.

## Extension points

| Need | Hook |
|---|---|
| Durable or shared run identity | `config.run_store`, or `store:` per run. Implement the `Store::Base` interface. |
| A different redaction policy | `config.redact`, or `redact:` per run. |
| Deterministic time in tests | `config.clock`, or `clock:` per run. |
| A shorter/longer approval window | `config.interrupt_ttl`, or `expires_in:` per run. |
| A different transport | Write to your own object: the gem needs `#write`. |
| A different server | Any Rack server; the Rails concern is one way to get a live response. |

## Non-goals

The gem is not an AG-UI SDK, a schema fork, a chat UI, a CopilotKit runtime, or a
second agent framework. It does not own conversation history, message ids, tool
authorization, or the decision to run a tool. It does not open connections, spawn
jobs or buffer frames.

See [Protocol Coverage]({% link _reference/protocol-coverage.md %}) for the wire events,
[Security and Deployment]({% link _advanced/security-and-deployment.md %}) for the threat model, and
[Rails Integration]({% link _advanced/rails-integration.md %}) for the adapter.
