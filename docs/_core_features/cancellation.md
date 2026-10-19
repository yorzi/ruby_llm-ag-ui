---
layout: default
title: Cancellation and Timeouts
nav_order: 5
description: Request cancellation on the authorized producer and distinguish it from a disconnected stream or provider timeout.
---

# {{ page.title }}

{{ page.description }}
{: .fs-6 .fw-300 }

After reading this guide, you will know:

* How to request cancellation on the producer's chat.
* Why aborting a browser request does not cancel server work.
* How provider timeouts become recorded failures.

## Request Cancellation in the Host

Resolve the active chat through your host's authenticated registry, using the
exact actor, thread, and run identity. The lookup below is application code:

```ruby
chat = authorized_active_chat_for(current_actor, thread_id: thread_id, run_id: run_id)
chat.cancel
```

RubyLLM checks cancellation cooperatively. When it raises `CancelledError`,
`Run` closes open content and persists a cancelled outcome. The client receives
`RUN_FINISHED` with `outcome.type` equal to `cancelled`. A cancellation request
is not proof that the run has stopped; wait for its recorded outcome.

Reject a cancellation for another actor, a previous run, or an inactive chat.
Otherwise a delayed cancellation can stop a later turn. The host serializes
operations on a mutable chat and delivers cancellation to the worker that owns
it. Calling `cancel` on a newly loaded chat in another process does not cancel
the original in-memory object. The gem supplies no cross-worker message broker.

## Keep HTTP Abort Separate

`HttpAgent#abortRun()` stops the browser's HTTP subscription. It does not call
`Chat#cancel`. While the producer remains alive, the gem detaches its failed
writer and continues to record the actual outcome. Reconnect with the same
input and run id after completion to read that result.

Wire an explicit, authorized cancellation endpoint when your application needs
server cancellation. The maintained client example shows both actions. See
[Client Example]({% link _advanced/client-example.md %}).

## Bound Provider Requests

Set provider transport limits through RubyLLM's context:

```ruby
context = RubyLLM.context do |config|
  config.request_timeout = 30
  config.max_retries = 0
end
chat = context.chat(model: 'gpt-4o-mini')
```

A provider request timeout ends the AG-UI run as failed, with a sanitized
`RUN_ERROR` code `transport_timeout`. Reconnecting reports the same failure
without a new provider request. A timeout is not a cancelled outcome.

The request timeout does not bound an entire multi-request turn or a local
tool. Provider retries can extend elapsed time. Put deadlines and cancellation
checkpoints in your tools and reconcile external effects before retrying an
uncertain action. Cancellation cannot undo a tool that already changed an
external system.

## Check the Offline Evidence

`spec/integration/provider_lifecycle_spec.rb` runs the real RubyLLM chat with an
intercepted HTTP request. It verifies timeout classification and cancellation
before a provider request. It uses synthetic configuration and makes no live
provider call. Browser fixtures separately exercise host cancellation and
HTTP abort; they do not establish a provider's cancellation latency.

## Next Steps

* [Streaming Runs]({% link _core_features/streaming-runs.md %}) - understand terminal outcomes.
* [Worker Recovery]({% link _advanced/worker-recovery.md %}) - close a run after confirmed worker death.
