---
layout: default
title: "Rails Integration"
nav_order: 1
description: Serve AG-UI runs from Rails with the optional controller concern and durable ActiveRecord store.
---

# {{ page.title }}

{{ page.description }}
{: .fs-6 .fw-300 }

After reading this guide, you will know:

* How to install the Rails adapter files.
* How to authenticate, select a chat, and stream a run.
* What the durable store and reconnect path provide.

The adapter is optional. It is what a Rails host gets for free: a controller
concern that serves the event stream, a durable run store backed by ActiveRecord,
a generator for both, and reconnect support.

Nothing under `lib/ruby_llm/ag_ui/rails/` loads unless `Rails::Railtie` is already
defined, so a pure-Ruby app pays nothing for it.

## Install

```bash
bundle add ruby_llm-ag_ui
bin/rails generate ruby_llm:ag_ui:install
bin/rails db:migrate
```

The generator writes two files:

- `db/migrate/*_create_ruby_llm_ag_ui_runs.rb`: one row per run, with a unique
  index on `(scope, thread_id, run_id)` and one on
  `(scope, thread_id, status)`.
- `config/initializers/ruby_llm_ag_ui.rb`: points `config.run_store` at
  `RubyLLM::AgUI::Rails::ActiveRecordStore` and lists the choices worth making.

The migration targets the host's own Rails version
(`ActiveRecord::Migration.current_version`), so it does not pin a schema version
you did not choose.

## The controller

```ruby
class AgentRunsController < ApplicationController
  include RubyLLM::AgUI::Rails::Streaming

  def create
    stream_ag_ui_run { |input| chat_for(input) }
  end
end
```

`stream_ag_ui_run` parses the body, resolves the chat, runs, and writes SSE. The
block receives the parsed `Input` and must return the chat for it.

Two methods are yours:

```ruby
# Required. Built from the authenticated request, never from the input.
def ag_ui_scope
  "tenant:#{current_tenant.id}:actor:#{current_user.id}"
end

# Optional. The state to publish on a reconnect, or nil (the default).
def ag_ui_state
  { 'orders' => current_user.visible_orders.map(&:as_json) }
end
```

`ag_ui_scope` has no default on purpose: raising a `ConfigurationError` is better
than quietly reserving every run under one shared scope. It bounds every store
lookup, so two actors using the same `threadId` cannot reach each other's runs.

`ag_ui_state` is only published when a completed run is served to a client that
reconnects. It is not replayed as deltas, and the gem never computes it; your
app knows what the client is looking at.

## What the client gets, and when

| Request | Response |
|---|---|
| Valid input, `Accept: text/event-stream` | `200`, SSE, one `data:` line per AG-UI event |
| `Accept` that cannot read SSE, including an effective `q=0` | `406` before resolving the chat or reserving a run |
| Empty, non-JSON, or schema-invalid body | `400` |
| Body past `config.max_input_bytes` | `413` |
| `threadId` the actor does not own, when the block raises `ActiveRecord::RecordNotFound` | `404` |
| Same `(scope, threadId, runId)` with different input | `409` |
| A live run that already has a stream | `409` |
| The same identity and input for a run that ended | `200`, `RUN_STARTED` + `STATE_SNAPSHOT` + the recorded terminal event |
| Client disconnects mid-run | no error; the record in the store is the outcome |

Refusals are decided before the response commits, so a client that cannot be
served gets a status code instead of a stream that stops mid-event. A disconnect
is not a run outcome: the run keeps its own record, and a reconnect server can
serve it.

## The store

`Rails::ActiveRecordStore` implements the same contract as `MemoryStore` and is
what makes run identity survive a worker:

- `reserve` inserts; a `RecordNotUnique` means another worker won, and the
  existing row is attached or refused by digest.
- `redeem_interrupt` uses a conditional update and revalidates competing
  decisions, so only one caller redeems an approval.
- `save` checks record revisions and refuses stale writers. Keep its returned
  record for the next update. See [Worker Recovery]({% link _advanced/worker-recovery.md %})
  before closing a run whose producer stopped.
- `find_interrupt` is scoped by `(scope, thread_id, interrupt_id)`, so an
  interrupt id is not a global key.

`scope`, `thread_id` and `run_id` are strings; the record itself is stored as
JSON **text** in `payload`, because a record is immutable and has no partial
update to model. The gem does the encoding, so the stored shape is exactly
`RunRecord#to_storage` on every database and Rails version, rather than whatever
the host's ActiveSupport JSON encoder produces.

Use `MemoryStore` only for a single process (development, tests, one Puma worker
with no restarts). It is per-process, and a retry after a restart is a new run.

## Resume, from the client's side

A pause is a `RUN_FINISHED` with an interrupt outcome:

```json
{"type":"RUN_FINISHED","threadId":"thread-1","runId":"run-1",
 "outcome":{"type":"interrupt","interrupts":[
   {"id":"9f2c...","reason":"tool_call_confirmation",
    "message":"Approve the cancel_order tool call?",
    "toolCallId":"call_1","expiresAt":"2026-10-18T12:15:00Z"}]}}
```

The client answers it on a **new run** for the same thread:

```json
{"threadId":"thread-1","runId":"run-2",
 "messages":[{"id":"m1","role":"user","content":"Cancel order 42."}],
 "resume":[{"interruptId":"9f2c...","status":"resolved"}]}
```

`status: "cancelled"` records a denial instead. Either way the interrupt must
still be pending, unexpired, and bound to the same tool call arguments the host
chat holds, or the run is refused before it is reserved.

The approval is a request, not a permission: re-authorize before the tool runs.

## Transport

`ActionController::Live` holds a thread for the life of the run and is the
simplest thing that streams correctly. Before production, know its two costs:

- **Threads.** A server with `N` workers and `T` threads can serve `T` concurrent
  streams. Long model calls make that a real limit.
- **Proxies.** `X-Accel-Buffering: no` is set for nginx, but any intermediary that
  buffers will turn the stream into one response at the end. `curl -N` is the
  quickest way to see whether yours does.

If you need to survive deploys, or to serve one run to several clients, run the
work elsewhere and have the controller read from your own broker. The gem gives
you the parts, not the relay: any object with `#write` is a stream, the run record
is durable, and `RubyLLM::AgUI::Reconnect` builds the events for a run that has
already ended. Two live streams for one run are refused rather than merged,
because a silent second stream duplicates the work.

## Testing a host app

The adapter's own specs live in `spec/rails_helper.rb`-based files and are not
auto-required. In your app, two kinds of test are usually enough:

1. A controller test that the refusals happen (no auth, wrong `Accept`, a
   `threadId` the actor does not own) and that a valid request yields an event
   stream.
2. A store test that the same identity twice does not execute twice, and that a
   resume replayed twice does not run the tool twice.

You do not need a real model for either: pass a chat double that plays
`before_tool_call`, `after_message`, `complete`, `waiting?`,
`awaiting_approval?`, `pending_approvals`, `approve` and `deny`, which is exactly
what `spec/support/fake_chat.rb` in this repository does.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| The whole response arrives at once | A buffering proxy, or `curl` without `-N` |
| `406` for every request | The client did not send `Accept: text/event-stream` |
| `ConfigurationError` about `ag_ui_scope` | The controller does not define it |
| `409` on a request the client thinks is new | The same `(scope, threadId, runId)` was used with different input |
| `409` on a second tab of the same run | A live run has one stream; serve the second client from your own relay |
| Tool results are `[redacted]` | Redaction is the default; configure `config.redact` |
| A run succeeds but the client shows nothing | The client was not sent the interrupt/resume flow it expected, or it re-sent a `runId` whose run had already ended |

## Next Steps

* [Approval and Resume]({% link _core_features/approval-and-resume.md %}) - answer a tool approval pause.
* [Reconnects and Run Identity]({% link _core_features/reconnects.md %}) - understand durable run records.
* [Security and Deployment]({% link _advanced/security-and-deployment.md %}) - review host authorization duties.
