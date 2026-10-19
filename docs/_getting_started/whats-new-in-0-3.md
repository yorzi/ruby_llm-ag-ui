---
layout: default
title: "What's New in 0.3"
nav_order: -1
description: Keep run outcomes independent from response transport failures.
---

# {{ page.title }}

{{ page.description }}
{: .fs-6 .fw-300 }

After reading this guide, you will know:

* How a run continues after its client disconnects.
* How to reconnect without executing a turn twice.
* Which lifecycle work remains planned.

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

## Development Status

Version 0.3 is unreleased. Cancellation wiring, cross-worker store tests, and
explicit worker-loss recovery remain development targets in the roadmap.
