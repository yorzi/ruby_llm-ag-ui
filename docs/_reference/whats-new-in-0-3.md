---
layout: default
title: "What's New in 0.3"
nav_order: 30
parent: Release History
description: Verify transport failure, scoped cancellation, and explicit worker recovery.
---

# {{ page.title }}

{{ page.description }}
{: .fs-6 .fw-300 }

After reading this guide, you will know:

* How a run continues after its client disconnects.
* How to reconnect without executing a turn twice.
* How to recover after confirmed worker loss.
* How host cancellation differs from HTTP abort and provider timeout.

## Keep the Recorded Outcome

```ruby
record = RubyLLM::AgUI::Run.new(chat: chat, input: input, scope: scope,
                              store: store).stream(to: response_stream)
```

If the response transport disconnects, the worker continues the same turn and
persists its real outcome. A failed terminal write cannot change an already
recorded result. This is not a background job: worker termination still stops
execution. See [Streaming Runs]({% link _core_features/streaming-runs.md %}).

## Reconnect with the Same Input

Resend the original input and run id after completion. The store returns its
recorded outcome without running the chat or tool again. A second stream while
the original is still running is refused. See
[Reconnects and Run Identity]({% link _core_features/reconnects.md %}).

## Recover Lost Workers Explicitly

After confirming a worker has stopped, load its authorized record and call
`store.recover(record)`. The recorded failure uses code `worker_lost` and keeps
the identity reserved. Stale record writes are refused by revision checks.
Storage acknowledgement failures propagate as `PersistenceError` rather than
inventing a terminal outcome. See
[Worker Recovery]({% link _advanced/worker-recovery.md %}).

## Cancel the Authorized Run

The client example now shows separate controls for host cancellation and HTTP
abort. Its cancel endpoint checks the fixture actor and exact run identity;
disconnecting the browser leaves the producer running. RubyLLM's HTTP timeout
is recorded as `transport_timeout`, without raw provider details. See
[Cancellation and Timeouts]({% link _core_features/cancellation.md %}).

Version 0.3 adds independent-process SQLite tests, including a producer killed
after a synthetic tool effect.
These tests do not establish live provider or other-database behavior.

Before updating, read [Upgrading]({% link _reference/upgrading.md %}) for worker
draining, the custom-store contract, and the JSON 2.x dependency requirement.
